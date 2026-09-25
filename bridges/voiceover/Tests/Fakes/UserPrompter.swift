// Hand-written stateful fake for the UserPrompter port, standing in for the human; no test may open a window.

import VoiceOverBridgeDomain

public final class FakeUserPrompter: UserPrompter {
	public struct CouldNotPresent: Error {
		public init() {}
	}

	public private(set) var presented: [String] = []
	public private(set) var cancelled: [PromptId] = []
	private var outcomes: [PromptId: PromptOutcome] = [:]
	private var next = 0

	public var fails = false

	public init() {}

	public private(set) var lastTicket: PromptId = ""

	public func present(_ prompt: String) throws -> PromptId {
		if fails { throw CouldNotPresent() }
		presented.append(prompt)
		next += 1
		lastTicket = "prompt-\(next)"
		return lastTicket
	}

	public func reply(for id: PromptId) -> PromptOutcome? {
		outcomes[id]
	}

	public func cancel(_ id: PromptId) {
		cancelled.append(id)
		outcomes.removeValue(forKey: id)
	}

	public func answer(_ text: String, to id: PromptId? = nil) {
		outcomes[id ?? lastTicket] = .answered(text)
	}

	public func dismiss(_ id: PromptId? = nil) {
		outcomes[id ?? lastTicket] = .dismissed
	}
}
