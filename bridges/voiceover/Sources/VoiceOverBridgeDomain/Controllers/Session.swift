// ROLE: controller -- one bridge session's LIFECYCLE and nothing
// command-specific: the handshake, one dispatch loop guarded by two watchdogs,
// and a teardown that runs on every exit path.
//
// HANDED (by Wiring): a MessageChannel, a Transcript, a Clock, a SessionConfig,
// the command map and the SessionSignals -- ports and configuration only. It
// does NOT hold the AdapterFactory: that lives inside the hello handler, because
// the mode is not known until hello has been read.
// BUILDS: the SessionContext every handler is handed.
//
// ONE LOOP, ONE PHASE FLAG. Before `hello` only `hello` is accepted and any
// failure ends the handshake; after it the session is tolerant -- an error frame
// and keep going -- because a test run must survive a command the agent got
// wrong. `while reason == nil` is the whole loop: every exit sets the reason,
// and a timed-out read sets nothing and polls again.
//
// THREADING. `run()` executes on the caller's thread, which is BridgeServer's
// accept thread. `requestTeardown` is the only method another thread may call,
// and it is the one the control dialog and a machine shutdown reach the session
// through. That asymmetry is deliberate: a session is not thread-safe, it is
// thread-CONFINED with one guarded door.
//
// THREE WATCHDOGS SINCE 13.6, and the third one is not keyed on absence. The
// heartbeat asks "is the server process alive?" and command-inactivity asks "is
// the agent still testing?"; the SILENCE CAP (spec 0032, protocol.md §6.1) asks
// the human's question -- how long have I been unable to hear my own machine? --
// and it is checked beside `checkDeadline` on EVERY path, including the
// timed-out one, because an agent that is busy but slow is not absent and no
// watchdog keyed on absence would ever fire for it.
//
// THE SAME CHECK RENEWS THE SILENCE LEASE, and that coupling is deliberate
// rather than convenient. On macOS the interception is a file the capture voice
// reads, and it EXPIRES: the session refreshes it while it lives, so a bridge
// that is SIGKILLed un-mutes the machine by doing nothing at all. Driving the
// renewal from this loop -- rather than from a timer of the adapter's own --
// means silence depends on the liveness of the very loop that can lift it, so a
// session thread wedged inside a handler gives the machine back instead of
// holding it mute with every watchdog still ticking.

import Foundation
import ScreenReaderWire

/// The per-session settings Wiring hands the controller.
///
/// THE TWO WINDOWS ARE SEPARATE ON PURPOSE. The heartbeat proves the harness
/// PROCESS is alive, and any message resets it. Command inactivity proves the
/// AGENT is still testing, and only a real command -- not a ping -- resets it. A
/// single timeout could not tell a busy agent from an abandoned socket.
public struct SessionConfig: Equatable, Sendable {
	/// The reader's own version, as `hello` will report it.
	public var readerVersion: String

	/// Nothing at all arrived for this long: the peer is presumed gone.
	public var heartbeatTimeout: Double

	/// No real command for this long: the agent has stopped testing.
	public var inactivityTimeout: Double

	/// Whether a human is expected at this machine (spec 0035). A machine fact,
	/// read from the bridge's configuration, defaulting to the safe direction --
	/// a machine nobody has configured is not one we may assume is empty.
	public var attended: Bool

	/// How long a silent session may leave that human unable to hear. Derived
	/// from the same machine setting as `attended`, in Wiring, so the handshake
	/// and the watchdog cannot disagree about it.
	public var silenceCap: SilenceCapPolicy

	public init(
		readerVersion: String,
		heartbeatTimeout: Double = 30.0,
		inactivityTimeout: Double = 120.0,
		attended: Bool = true,
		silenceCap: SilenceCapPolicy = .attendedDefault
	) {
		self.readerVersion = readerVersion
		self.heartbeatTimeout = heartbeatTimeout
		self.inactivityTimeout = inactivityTimeout
		self.attended = attended
		self.silenceCap = silenceCap
	}
}

public final class Session {
	/// Whether the handshake has completed. Private to the dispatch loop.
	private enum Phase {
		case preHello
		case established
	}

	private let channel: any MessageChannel
	private let transcript: any Transcript
	private let clock: any Clock
	private let config: SessionConfig
	private let handlers: [String: any CommandHandler]
	private let signals: any SessionSignals
	private let context: SessionContext

	private var phase: Phase = .preHello

	// Watchdog bookkeeping, in monotonic seconds; seeded by run().
	private var lastMessageAt: Double = 0
	private var lastCommandAt: Double = 0

	/// The cross-thread door. `externalReason` is written by another thread and
	/// read by the loop at its next wakeup; `reason` is the loop's own and is
	/// touched by nothing else.
	private let externalLock = NSLock()
	private var externalReason: TeardownReason?

	private var reason: TeardownReason?
	private var tornDown = false

	/// The third watchdog. Nil until a SILENT session establishes: a cap on a
	/// session that suppresses nothing would be measuring a silence that is not
	/// happening.
	private var silenceCap: SilenceCap?

	public init(
		channel: any MessageChannel,
		transcript: any Transcript,
		clock: any Clock,
		config: SessionConfig,
		handlers: [String: any CommandHandler],
		signals: any SessionSignals
	) {
		self.channel = channel
		self.transcript = transcript
		self.clock = clock
		self.config = config
		self.handlers = handlers
		self.signals = signals
		var close: (TeardownReason) -> Void = { _ in }
		self.context = SessionContext(
			clock: clock,
			transcript: transcript,
			attended: config.attended,
			silenceCapPolicy: config.silenceCap,
			close: { close($0) }
		)
		// Tied after construction because the context's close capability IS this
		// session's, and a class cannot hand out `self` before it is initialised.
		// The indirection is one closure deep and never nil.
		close = { [weak self] reason in self?.requestTeardown(reason) }
	}

	// -- public API ----------------------------------------------------------

	/// Run the whole session on the caller's thread. Always tears down.
	public func run() {
		let now = clock.monotonic()
		lastMessageAt = now
		lastCommandAt = now
		defer { teardown() }
		loop()
	}

	/// The context, for anything outside the loop that needs to reach the live
	/// session. Read-only from here; the loop owns every field on it.
	public var sessionContext: SessionContext { context }

	/// Ask the session to end. Thread-safe, and honoured at the loop's next
	/// wakeup -- which is what makes teardown cooperative rather than a kill.
	/// The first request wins; a later one is ignored rather than overwriting the
	/// reason the session actually ended for.
	public func requestTeardown(_ reason: TeardownReason) {
		externalLock.lock()
		defer { externalLock.unlock() }
		if externalReason == nil {
			externalReason = reason
		}
	}

	// -- the one dispatch loop -----------------------------------------------

	private func loop() {
		while reason == nil {
			absorbExternal()
			if reason != nil { break }

			let read: ChannelRead
			do {
				read = try channel.read()
			} catch is ChannelClosed {
				reason = .channelClosed
				break
			} catch {
				// A line arrived and could not be read. Bytes mean the peer is
				// alive, so mid-session this is noted and survived; before the
				// handshake it is not our client at all.
				onUnreadable(error)
				checkSilence()
				checkDeadline()
				continue
			}

			if read == .timedOut {
				checkSilence()
				checkDeadline()
				continue
			}
			guard case .message(let raw) = read else { continue }

			touchHeartbeat()
			dispatch(raw)
			// Refreshed AFTER dispatch as well, so a handler that blocks past the
			// heartbeat window does not kill the session the instant it returns.
			// The peer's silence while the handler ran was our doing, not evidence
			// that it died.
			touchHeartbeat()
			checkSilence()
			checkDeadline()
		}
	}

	private func absorbExternal() {
		externalLock.lock()
		let pending = externalReason
		externalLock.unlock()
		if let pending, reason == nil {
			reason = pending
		}
	}

	private func onUnreadable(_ error: any Error) {
		if phase == .preHello {
			reason = .handshakeFailed
			return
		}
		touchHeartbeat()
		transcript.note("unreadable message: \(describe(error))")
	}

	private func touchHeartbeat() {
		lastMessageAt = clock.monotonic()
	}

	private func checkDeadline() {
		guard reason == nil else { return }
		let now = clock.monotonic()
		if now - lastMessageAt >= config.heartbeatTimeout {
			// Before the handshake, silence is a failed handshake rather than a
			// lost heartbeat: nothing was ever established to lose.
			reason = phase == .preHello ? .handshakeFailed : .heartbeatTimeout
			return
		}
		if phase == .established, now - lastCommandAt >= config.inactivityTimeout {
			reason = .inactivityTimeout
		}
	}

	/// Renew the silence lease, and act on the third watchdog.
	///
	/// RENEWAL COMES FIRST AND IS UNCONDITIONAL, because it is the cheap half and
	/// the one whose omission is dangerous: a lease left unrenewed expires, which
	/// is safe, while a lease renewed by a session that should have lifted is not.
	private func checkSilence() {
		guard let silence = context.adapters?.silenceControl else { return }
		silence.renew()
		guard let cap = silenceCap else { return }
		switch cap.check(clock.monotonic()) {
		case .none:
			return
		case .warn:
			transcript.note("silence cap: warning the human that they cannot hear their machine")
			guarded("the silence-cap warning") { try self.signals.silenceWarning() }
		case .lift:
			// THE GUARANTEE, not a courtesy: the human gets their machine back.
			// Capture is untouched -- the same entries, at the same indices, with
			// the same stamps -- so the agent loses its silence and none of its
			// evidence (protocol.md §6.1).
			transcript.note("silence cap: LIFTED -- the human hears their machine again")
			guarded("lifting the silence") { try silence.passThrough() }
			guarded("the silence-cap lift cue") { try self.signals.silenceLifted() }
		}
	}

	// -- dispatch ------------------------------------------------------------

	private func dispatch(_ raw: [String: JSONValue]) {
		let request: Request
		do {
			request = try JSONValue.object(raw).decoded(as: Request.self)
		} catch {
			replyCommandError(id: extractID(raw), "invalid request: \(describe(error))")
			return
		}

		let preHello = phase == .preHello
		guard let handler = handlers[request.cmd], !(preHello && !handler.availableBeforeHello) else {
			if preHello {
				replyCommandError(id: request.id, "handshake: expected hello")
			} else {
				reply(id: request.id, error: "unknown command: '\(request.cmd)'")
			}
			return
		}
		if !preHello, handler.availableBeforeHello {
			reply(id: request.id, error: "session already established")
			return
		}

		// A real command resets inactivity; a ping proves liveness only.
		if handler.resetsInactivity {
			lastCommandAt = clock.monotonic()
		}

		let result: any Encodable
		do {
			result = try handler.execute(context, request)
		} catch {
			replyCommandError(id: request.id, describe(error))
			return
		}

		reply(id: request.id, result: result)
		if preHello {
			phase = .established
			// The third watchdog starts HERE, seeded at the moment the session cue
			// is about to sound -- which is honest, because that cue is itself one
			// of the sounds that reach the human past the suppression.
			if context.mode == .silent {
				silenceCap = SilenceCap(policy: config.silenceCap, now: clock.monotonic())
			}
			// Two ascending tones, then the persona this session declared: the
			// tones say control was taken, the words say what it was taken AS.
			// Guarded, because a courtesy is never worth a session.
			guarded("the session-start cue") { try self.signals.sessionStarted(persona: self.context.persona) }
		}
	}

	// -- teardown ------------------------------------------------------------

	/// Runs exactly once, on every exit path.
	///
	/// EVERY STEP THAT CAN FAIL IS INDIVIDUALLY GUARDED, so a failure in one
	/// never skips the rest. That matters more here than anywhere else in the
	/// bridge: the macOS form of hard invariant 3 (13.6) is a restoration that
	/// runs in this method, and a cue that could not be played must not be able
	/// to leave a blind user with a screen reader that has been muted on their
	/// behalf.
	///
	/// The steps that DO NOT throw need no guard, and Swift is what makes that
	/// checkable rather than hopeful: the transcript and the channel promise in
	/// their own types that they swallow their IO failures, so a blanket
	/// try/catch around them would be catching nothing.
	///
	/// Steps for state `hello` never reached are naturally skipped, which is what
	/// the optionals on the context buy.
	private func teardown() {
		if tornDown { return }
		tornDown = true
		let ending = reason ?? .external

		// Stop what the handshake started. Unconditional on how the session
		// ended, and naturally skipped when `hello` never ran, because the
		// adapter set is nil until it does.
		//
		// NO GUARD, AND THE TYPE IS WHY: `SpeechSource.stop` does not throw --
		// see the port for both halves of that argument -- so a try/catch here
		// would be catching nothing. It is also idempotent, so a source that was
		// never started is safe to stop.
		context.adapters?.speechSource.stop()

		// HARD INVARIANT 3, IN ITS MACOS FORM. Both steps run on EVERY teardown
		// path, whatever ended the session, and each is guarded so a failure in one
		// cannot skip the other.
		//
		// NEITHER IS THE GUARANTEE, and that is the thing to understand before
		// changing this block. The guarantee is that the silence marker EXPIRES: a
		// SIGKILL, a panic and a power cut all skip every line below, and the
		// machine still speaks again within one lease. What these two buy is that
		// the ORDINARY case is immediate rather than up to a lease late.
		//
		// PASS-THROUGH FIRST, THE VOICE SECOND. If the restoration fails, a
		// released marker still leaves the human hearing their machine through our
		// voice -- degraded, and safe. The reverse order would leave a window where
		// the reader is back on the user's own voice while a marker still says
		// silence, which is nothing at all.
		if let adapters = context.adapters {
			// NO GUARD, AND THE TYPE IS WHY: `release` does not throw -- it is a
			// best-effort delete over a mechanism whose guarantee is the expiry --
			// so a try/catch here would be catching nothing.
			adapters.silenceControl.release()
			if let previous = context.previousVoice {
				guarded("restoring the user's own voice") {
					try adapters.providerLifecycle.restoreVoice(previous)
				}
			}
		}

		transcript.sessionClosed(reason: ending.rawValue)
		if phase == .established {
			// Two descending tones: control released. Only for a session that
			// actually established -- a connection that never said hello was never
			// announced, so there is nothing to un-announce.
			guarded("the session-end cue") { try self.signals.sessionEnded() }
		}
		channel.close()
	}

	/// Run one step that may fail, and never let its failure stop the others.
	///
	/// IT IS NOT SILENT ANY MORE, and 13.6 is why: a restoration that failed is
	/// the one failure in this file a human needs to know about, because it is
	/// the difference between "my machine came back" and "my machine is still on
	/// a voice I did not choose". The step names itself so the transcript says
	/// which one.
	private func guarded(_ step: String, _ action: () throws -> Void) {
		do {
			try action()
		} catch {
			transcript.note("\(step) failed: \(describe(error))")
		}
	}

	// -- reply helpers -------------------------------------------------------

	private func reply(id: Int, result: any Encodable) {
		do {
			write(try Response.succeeded(id: id, with: result))
		} catch {
			// The result did not encode -- a bug in a handler's own shape, not a
			// peer fault. The agent is told, rather than left waiting for a frame
			// that will never come.
			write(Response.failed(id: id, message: "result could not be encoded: \(describe(error))"))
		}
	}

	private func reply(id: Int?, error message: String) {
		guard let id else {
			// No id to attribute the error to; the transcript still records it.
			transcript.note("unattributable error: \(message)")
			return
		}
		write(Response.failed(id: id, message: message))
	}

	/// Reply with an error, and end the handshake if we are still in it.
	private func replyCommandError(id: Int?, _ message: String) {
		reply(id: id, error: message)
		if phase == .preHello {
			reason = .handshakeFailed
		}
	}

	private func write(_ response: Response) {
		// A channel that died mid-reply is observed by the next read, which
		// raises ChannelClosed and tears the session down. So a failed write is
		// swallowed rather than crashing the loop before the read can see it.
		try? channel.write(response)
	}

	private func extractID(_ raw: [String: JSONValue]) -> Int? {
		if case .int(let id) = raw["id"] {
			return id
		}
		return nil
	}

	/// One rendering for every error the loop reports, so a ValidationError reads
	/// as `HelloParams.mode: ...` rather than as Swift's struct description.
	private func describe(_ error: any Error) -> String {
		if let described = error as? any CustomStringConvertible {
			return described.description
		}
		return String(describing: error)
	}
}
