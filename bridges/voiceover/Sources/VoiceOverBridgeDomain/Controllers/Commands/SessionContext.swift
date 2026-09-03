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

	/// The voice the user had chosen for themselves, read at the handshake and
	/// put back at teardown. Nil means there is nothing to restore -- either the
	/// store could not be read, or what it said was OUR OWN voice, which a
	/// previous session left behind when it died without restoring. Recording
	/// that as "the user's voice" would restore the capture voice at teardown and
	/// hand the extension itself as the pass-through voice, which is infinite
	/// recursion (spec 0046, Rule 0's first caveat).
	///
	/// SET BEFORE THE VOICE IS CHANGED, not after, so a handshake that fails
	/// half-way still leaves teardown holding what the user had.
	public var previousVoice: String?

	/// The third watchdog itself, once a SILENT session has established one.
	///
	/// IT LIVES HERE RATHER THAN INSIDE THE SESSION SINCE 13.10, and that is a
	/// layout amendment with its why: what RESETS this clock is sound the human
	/// actually hears (protocol.md §6.1), and from this entry on two of those
	/// sounds are commands -- `announce` and `askUser`. A handler sees the context
	/// and nothing else, so the cap either moves here or the context grows a
	/// second closure into the session for the sole purpose of forwarding one
	/// call. The session still owns the POLICY: it creates the cap at the
	/// handshake and it is the only thing that acts on `check`.
	///
	/// Nil in a live session, and nil on a machine whose owner declared it
	/// unattended: a cap on a session that suppresses nothing would be measuring a
	/// silence that is not happening.
	public var silenceCap: SilenceCap?

	/// The one question currently in front of the human, if any (13.10).
	///
	/// ONE AT A TIME, enforced by the AskUser controller: two open windows would
	/// leave a human unable to tell which ticket they were answering. Hung on the
	/// context rather than held by a handler because three different things need
	/// it -- the poll that collects the answer, the dispatch loop (a human reading
	/// a prompt IS hearing their machine, so the cap stays fresh while it is open)
	/// and teardown, which takes the window away.
	public var outstandingPrompt: UserPrompt?

	/// Whether this machine bounds its silences, and by how much. A MACHINE fact
	/// like `attended` and derived from the same one, carried here so the
	/// handshake can report it and the session can build its third watchdog from
	/// ONE source rather than two that agree today.
	public let silenceCapPolicy: SilenceCapPolicy

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
		silenceCapPolicy: SilenceCapPolicy = .attendedDefault,
		close: @escaping (TeardownReason) -> Void
	) {
		self.clock = clock
		self.transcript = transcript
		self.attended = attended
		self.silenceCapPolicy = silenceCapPolicy
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

	/// The human just heard their own machine: a fresh silence window.
	///
	/// CALLED FOR EXACTLY THE SOUNDS THAT REACH THEM PAST THE SUPPRESSION -- the
	/// session cue, `announce`, and the question `askUser` puts to them -- and for
	/// nothing else. Four hundred gestures in ninety seconds reset nothing,
	/// because they told the human nothing (protocol.md §6.1).
	///
	/// AFTER THE SOUND WAS MADE, never before: the clock records when they were
	/// told, not when we decided to tell them.
	public func humanHeard() {
		silenceCap?.heard(clock.monotonic())
	}

	/// Ask the session to end. Cooperative: the loop honours it at its next
	/// wakeup, which is what lets `bye` be acknowledged before the connection
	/// closes.
	public func close(_ reason: TeardownReason) {
		closeSession(reason)
	}
}
