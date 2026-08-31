// ROLE: entity -- one outstanding question to the human: its ticket, how long it
// stays open, and whether asking it cost the session its silence.
//
// PURE, AND IT HOLDS NO ANSWER. The answer lives in the prompter's own table,
// because the window that collects it is AppKit's and the poll that reads it is
// the adapter's (see UserPrompter, whose header carries the argument for polling
// rather than awaiting). What has to be pure is the WINDOW -- a deadline is
// arithmetic on a clock reading, and arithmetic is exactly what belongs in an
// entity rather than in a view.
//
// BUILT BY: the AskUser controller, once per `askUser`, and hung on the
// SessionContext so `waitForUserReply`, the dispatch loop and teardown all see
// the same one. READ BY: WaitForUserReply (expiry), the Session (the silence cap
// stays fresh while a window is open, and teardown takes the window away).
//
// ONE AT A TIME, and the controller enforces it: two open windows would leave a
// human looking at two questions with no way to tell which ticket they were
// answering, and would let an agent lose track of which one it was polling.
//
// `suspendedSilence` IS RECORDED RATHER THAN RE-DERIVED. Asking a question of
// somebody whose screen reader this session has muted is asking them to answer
// a dialog they cannot hear, so `askUser` lets the machine speak again while the
// window is open (protocol.md §5: `suppressing` is false then). Whether it did
// is a fact about THIS prompt -- a live session suspended nothing -- and the
// command that closes the window has to put back exactly what the command that
// opened it took.

public final class UserPrompt {
	/// How long a prompt stays answerable, in seconds. protocol.md §5's number:
	/// the poll's own timeout bounds one `waitForUserReply`, and this bounds the
	/// window itself, so an agent that stops polling does not leave a question on
	/// somebody's screen forever.
	public static let window: Double = 300.0

	public let ticket: PromptId
	public let prompt: String
	private let openedAt: Double
	private let lifetime: Double

	/// Whether opening this window lifted a silent session's suppression, and so
	/// whether closing it must put that suppression back.
	public var suspendedSilence = false

	public init(
		ticket: PromptId,
		prompt: String,
		now: Double,
		lifetime: Double = UserPrompt.window
	) {
		self.ticket = ticket
		self.prompt = prompt
		self.openedAt = now
		self.lifetime = lifetime
	}

	/// Whether the window has closed on its own. Answered from a clock reading
	/// the caller took, like everything else pure in this bridge.
	public func isExpired(_ now: Double) -> Bool {
		now - openedAt >= lifetime
	}

	/// How much of the window is left, never negative -- so a poll can be bounded
	/// by the window as well as by its own timeout without the two disagreeing
	/// about a wait of minus four seconds.
	public func remaining(_ now: Double) -> Double {
		max(0, lifetime - (now - openedAt))
	}
}
