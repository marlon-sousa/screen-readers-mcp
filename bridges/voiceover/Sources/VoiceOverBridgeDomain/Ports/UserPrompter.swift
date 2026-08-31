// ROLE: port -- the bridge's channel FROM the human: put a question in front of
// them, and collect the answer whenever it arrives.
//
// IMPLEMENTED BY: AppKitUserPrompter (adapters), over the PromptWindow seam;
// FakeUserPrompter (Tests/Fakes).
// BUILT BY: Wiring, once per process, and handed to the session in the
// AdapterSet. USED BY: the AskUser and WaitForUserReply controllers.
// OWNS: `PromptId` and `PromptOutcome`, this port's own types, per the repo's
// rule that a port's DTOs live in its file.
//
// ============================================================================
// THREE METHODS AND NO WAITING, WHICH IS THE ONE DESIGN QUESTION SPEC 0046 LEFT
// OPEN FOR THIS ENTRY. RESOLVED HERE, WITH ITS WHY.
// ============================================================================
//
// `askUser` and `waitForUserReply` are TWO commands (protocol.md §5): the agent
// asks, is handed a ticket, and collects the answer later -- possibly much
// later, and possibly never. So the port cannot be a synchronous
// `ask(_:) -> String`, and the alternative that reads better -- a continuation
// the session thread awaits -- was DECLINED for a reason specific to this
// bridge: that thread also RENEWS THE SILENCE LEASE (13.6). Parking it on a
// human's decision would let the lease expire while somebody reads a dialog,
// which is the exact failure 13.6's design exists to make impossible, and it
// would do so on the one path where the human is being asked a question about
// their own machine. So a prompt is PRESENTED and its answer is POLLED, nothing
// blocks either thread, and `waitForUserReply` is a bounded wait against the
// same `Clock` port every other wait in this bridge uses.
//
// THE ADAPTER MINTS THE ID, not the domain, and that is deliberate: the window
// and its answer live in the same table, so the thing that owns the table owns
// the key. The domain's `UserPrompt` entity holds that id alongside the window's
// deadline, which is the part that has to be pure to be testable.
//
// EVERY METHOD IS CALLED FROM THE SESSION THREAD and the AppKit implementation
// marshals to the main thread itself. A view is not allowed to block, and
// neither is this: `reply(for:)` answers with what it has, which is `nil` when
// the human has not finished.

/// The ticket an agent polls with. A string because it crosses the wire as one
/// (`AskUserResult.ticket`); opaque to everything but the prompter that minted
/// it.
public typealias PromptId = String

/// How a prompt ended. `nil` from `reply(for:)` means it has not ended.
public enum PromptOutcome: Equatable, Sendable {
	/// The human answered. The text may be empty -- an empty answer given on
	/// purpose is still an answer, and the wire carries it as one.
	case answered(String)

	/// The human closed the prompt without answering, or the bridge cancelled it.
	/// A REAL OUTCOME AND NOT AN ERROR: protocol.md's `answered: false` is what an
	/// agent branches on, exactly as `waitForSpeech`'s `found: false` is.
	case dismissed
}

/// Why a question could not be put to the human at all.
public struct PrompterError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol UserPrompter: AnyObject {
	/// Put `prompt` in front of the human and return at once with its id.
	///
	/// NEVER BLOCKS. It returns as soon as the window has been asked for, not
	/// when it has been drawn and not when it has been answered.
	func present(_ prompt: String) throws -> PromptId

	/// What the human has done about `id` so far: `nil` while the window is still
	/// open, and once an outcome is available it stays available until the prompt
	/// is cancelled, so a poll that arrives late still gets the answer.
	func reply(for id: PromptId) -> PromptOutcome?

	/// Take the window away and forget the prompt.
	///
	/// Idempotent, and it does NOT throw: it runs on the answer path, on the
	/// expiry path and at teardown, and a window that could not be dismissed must
	/// never be able to stop a session from ending.
	func cancel(_ id: PromptId)
}
