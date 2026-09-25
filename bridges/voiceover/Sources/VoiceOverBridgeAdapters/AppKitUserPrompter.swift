// ROLE: adapter that implements the UserPrompter port over the PromptWindow seam, owning tickets and answers.
// BUILT BY: Wiring, once per process.
// USED BY: the AskUser and WaitForUserReply controllers, through the port.
// A table that is polled, never awaited: the thread that would await an answer renews the silence lease.
// The seam's callback arrives on the main thread, so every access takes the lock, never across a seam call.
// The first outcome wins and a cancelled prompt accepts none, so a window reporting twice keeps its answer.
// An answer stays until the prompt is cancelled, so a poll that arrives late still gets it.

import Foundation
import VoiceOverBridgeDomain

public final class AppKitUserPrompter: UserPrompter {
	private let window: any PromptWindow
	private let mintId: () -> PromptId

	private let lock = NSLock()
	private var outcomes: [PromptId: PromptOutcome] = [:]
	private var awaiting: Set<PromptId> = []

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
