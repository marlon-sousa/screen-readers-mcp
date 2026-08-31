// ROLE: adapter -- IMPLEMENTS the UserPrompter domain port. It owns the ticket
// and the small table of answers, over the PromptWindow seam.
//
// BUILT BY: Wiring, once per process. USED BY: the AskUser and WaitForUserReply
// controllers, through the port. HOLDS: the PromptWindow seam.
//
// A TABLE AND A POLL, NOT A CONTINUATION, and the reason is in UserPrompter's
// header: the thread that would await an answer is the one renewing the silence
// lease, so a human reading a dialog would un-mute the machine 13.6 promised to
// keep quiet. Here the answer simply lands in a dictionary whenever it lands,
// and whoever polls next finds it.
//
// TWO THREADS TOUCH THIS OBJECT, WHICH IS WHY EVERY ACCESS TAKES THE LOCK.
// `present`, `reply` and `cancel` are called on the session thread; the seam's
// callback arrives on AppKit's main thread, at a moment nothing here controls.
// The lock is held only around the dictionary -- never across the call into the
// seam, which would be a main-thread hop taken while holding a lock the main
// thread may want.
//
// THE FIRST OUTCOME WINS, AND A CANCELLED PROMPT ACCEPTS NONE. A window that
// reports twice -- answered, and then closed -- must not turn an answer into a
// dismissal, and the human pressing return before the window tears itself down
// is exactly that sequence. The same set is what stops a `close` we asked for
// arriving back as a dismissal and re-populating a table entry the poll has
// already taken away.
//
// AN ANSWER OUTLIVES ITS WINDOW ON PURPOSE. It stays in the table until somebody
// cancels the prompt, so an agent whose poll arrived a moment late still gets the
// answer instead of an empty window and a lost decision.

import Foundation
import VoiceOverBridgeDomain

public final class AppKitUserPrompter: UserPrompter {
	private let window: any PromptWindow
	private let mintId: () -> PromptId

	private let lock = NSLock()
	private var outcomes: [PromptId: PromptOutcome] = [:]
	/// The prompts whose outcome is still to come. Membership is what makes "the
	/// first outcome wins" true and what keeps a cancelled prompt from being
	/// re-entered by its own closing.
	private var awaiting: Set<PromptId> = []

	/// `mintId` is injected so a test can make tickets predictable; the default is
	/// a UUID, which is what the agent sees on the wire. It decides nothing else:
	/// the ticket is opaque to everything but this class.
	public init(window: any PromptWindow, mintId: @escaping () -> PromptId = { UUID().uuidString }) {
		self.window = window
		self.mintId = mintId
	}

	public func present(_ prompt: String) throws -> PromptId {
		let id = mintId()
		lock.lock()
		awaiting.insert(id)
		lock.unlock()
		window.open(id: id, prompt: prompt) { [weak self] outcome in
			self?.record(id, outcome)
		}
		return id
	}

	public func reply(for id: PromptId) -> PromptOutcome? {
		lock.lock()
		defer { lock.unlock() }
		return outcomes[id]
	}

	public func cancel(_ id: PromptId) {
		lock.lock()
		outcomes.removeValue(forKey: id)
		awaiting.remove(id)
		lock.unlock()
		window.close(id)
	}

	private func record(_ id: PromptId, _ outcome: PromptOutcome) {
		lock.lock()
		defer { lock.unlock() }
		guard awaiting.remove(id) != nil else { return }
		outcomes[id] = outcome
	}
}
