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
// WHAT IS NOT HERE YET, and where it goes: the SILENCE CAP is the third watchdog
// (spec 0032) and it arrives with 13.6, because a cap on a session that cannot
// suppress anything measures nothing. Its shape in lane 1 is a check beside
// `checkDeadline` on every path, including the timed-out one -- an agent that is
// busy but slow is not absent, so no watchdog keyed on absence ever fires for it.

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

	public init(
		readerVersion: String,
		heartbeatTimeout: Double = 30.0,
		inactivityTimeout: Double = 120.0,
		attended: Bool = true
	) {
		self.readerVersion = readerVersion
		self.heartbeatTimeout = heartbeatTimeout
		self.inactivityTimeout = inactivityTimeout
		self.attended = attended
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
				checkDeadline()
				continue
			}

			if read == .timedOut {
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
			// Two ascending tones, then the persona this session declared: the
			// tones say control was taken, the words say what it was taken AS.
			// Guarded, because a courtesy is never worth a session.
			guarded { try self.signals.sessionStarted(persona: self.context.persona) }
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

		// WHERE 13.6's RESTORATION GOES: right here, before the transcript is
		// closed and before the channel is, guarded like everything else, and
		// unconditional on how the session ended. It is left as this comment
		// rather than as an empty guarded call, because a call that does nothing
		// reads like a step that already works.

		transcript.sessionClosed(reason: ending.rawValue)
		if phase == .established {
			// Two descending tones: control released. Only for a session that
			// actually established -- a connection that never said hello was never
			// announced, so there is nothing to un-announce.
			guarded { try self.signals.sessionEnded() }
		}
		channel.close()
	}

	private func guarded(_ action: () throws -> Void) {
		do {
			try action()
		} catch {
			// Teardown must complete on every path, so a failure in one step is
			// swallowed and the remaining steps still run.
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
