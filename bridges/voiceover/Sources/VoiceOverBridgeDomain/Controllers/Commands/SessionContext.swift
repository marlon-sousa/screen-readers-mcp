// ROLE: PARAMETER OBJECT -- the per-session bundle every handler is handed,
// plus exactly one lifecycle capability.
//
// BUILT BY: the Session, once, and handed to every `execute`. POPULATED BY: the
// Hello handler, which is the only command that may fill in the fields that do
// not exist before a handshake.
//
// IT IS NOT AN ADAPTER, and saying so is the point of this header. It does no
// IO, implements no port and knows nothing about macOS; it holds what a handler
// would otherwise be given as six arguments. AGENTS.md records mislabelling this
// as an adapter as a learned mistake, so it is named correctly here.
//
// THE OPTIONALS ARE THE HANDSHAKE, NOT SLOPPINESS. `mode` and `adapters` do not
// exist until `hello` has been answered, and a handler that reads one before
// then is a handler that would have run before the handshake -- which the
// dispatch loop already refuses. Optional is how that fact is spelled in the
// type rather than in a comment.

import ScreenReaderWire

public final class SessionContext {
	public let clock: Clock
	public let transcript: Transcript

	/// Whether a human is expected at this machine (spec 0035). A MACHINE fact,
	/// read from the bridge's own configuration and never from the wire, so it is
	/// fixed for the session's whole life.
	public let attended: Bool

	/// The capture mode this session was established in. Nil before `hello`.
	public var mode: CaptureMode?

	/// The reader edge, built from the mode. Nil before `hello`, and set BEFORE
	/// anything is started, so teardown can stop what was started even if a
	/// later step of the handshake throws.
	public var adapters: AdapterSet?

	/// This session's captured speech. Created by the hello handler, fed by the
	/// speech source's own thread, read by the five speech handlers.
	///
	/// SESSION-SCOPED, NOT PROCESS-SCOPED: a ring does not outlive the run it
	/// belongs to, so indices always mean what the agent that took them thought
	/// they meant.
	public var speech: SpeechBuffer?

	/// What the agent declared this session is standing in for (spec 0029).
	/// Recorded as received and never validated here: a bridge that rejected an
	/// unfamiliar persona would refuse a session over a word.
	public var persona: String = ""

	/// The session's ONE lifecycle capability: ask it to end, with a reason.
	/// Wired to `Session.requestTeardown`, so `bye` and an external stop share a
	/// single path.
	private let closeSession: (TeardownReason) -> Void

	public init(
		clock: Clock,
		transcript: Transcript,
		attended: Bool,
		close: @escaping (TeardownReason) -> Void
	) {
		self.clock = clock
		self.transcript = transcript
		self.attended = attended
		self.closeSession = close
	}

	/// The speech buffer, or a readable failure if there is none.
	///
	/// EVERY CALLER IS A HANDLER THAT RUNS AFTER `hello`, and `hello` always
	/// installs a buffer, so the failure is unreachable through the dispatch
	/// loop -- which is exactly why it is a thrown error rather than a crash: an
	/// unreachable case that is wrong takes one command with it here, and takes
	/// the user's screen reader with it there.
	public func speechBuffer() throws -> SpeechBuffer {
		guard let speech else {
			throw CommandError("the speech buffer was read before `hello` installed it")
		}
		return speech
	}

	/// Ask the session to end. Cooperative: the loop honours it at its next
	/// wakeup, which is what lets `bye` be acknowledged before the connection
	/// closes.
	public func close(_ reason: TeardownReason) {
		closeSession(reason)
	}
}
