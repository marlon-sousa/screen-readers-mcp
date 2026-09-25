// ROLE: port -- put a question in front of the human, and collect the answer whenever it arrives.
// IMPLEMENTED BY: AppKitUserPrompter, over the PromptWindow seam; FakeUserPrompter.
// BUILT BY: Wiring, once per process, and handed to the session in the AdapterSet.
// USED BY: the AskUser and WaitForUserReply controllers.
// Nothing blocks: the session thread also renews the silence lease, and parking it on a human's decision would let the lease expire.
// Every method is called from the session thread; the AppKit implementation marshals to the main thread itself.

public typealias PromptId = String

public enum PromptOutcome: Equatable, Sendable {
	/// The text may be empty, and is still an answer.
	case answered(String)

	/// Closed without answering, or cancelled by the bridge: a real outcome, not an error.
	case dismissed
}

public struct PrompterError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol UserPrompter: AnyObject {
	func present(_ prompt: String) throws -> PromptId

	/// `nil` while the window is open; an outcome stays available until cancelled, so a late poll still gets it.
	func reply(for id: PromptId) -> PromptOutcome?

	/// Idempotent and never throws: it runs at teardown, where a stuck window must never stop a session ending.
	func cancel(_ id: PromptId)
}
