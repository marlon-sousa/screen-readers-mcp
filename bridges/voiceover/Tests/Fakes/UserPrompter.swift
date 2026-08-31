// A hand-written stateful fake for the UserPrompter port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/UserPrompter.swift.
//
// IT EXISTS TO MAKE ONE MISTAKE UNAVAILABLE: no test may open a window on the
// developer's screen, take their focus, or make their screen reader announce a
// dialog nobody asked for.
//
// IT IS THE HUMAN, AND THAT IS WHY IT HOLDS STATE RATHER THAN RECORDING CALLS.
// The whole shape of `askUser` / `waitForUserReply` is that an answer arrives
// LATER, on somebody else's schedule -- so a test drives this fake the way a
// person drives a dialog: the prompt goes up, `answer(...)` or `dismiss(...)`
// happens at a moment the test chooses, and the poll finds it.

import VoiceOverBridgeDomain

public final class FakeUserPrompter: UserPrompter {
	/// Something a window server does when there is no session to draw in.
	public struct CouldNotPresent: Error {
		public init() {}
	}

	public private(set) var presented: [String] = []
	public private(set) var cancelled: [PromptId] = []
	private var outcomes: [PromptId: PromptOutcome] = [:]
	private var next = 0

	/// When true, `present` throws instead of putting a window up.
	public var fails = false

	public init() {}

	/// The ticket the next `present` will mint. Predictable on purpose: a test
	/// asserting a round trip should be able to write the ticket down.
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

	// -- standing in for the person --------------------------------------------

	/// The human typed something and pressed the button.
	public func answer(_ text: String, to id: PromptId? = nil) {
		outcomes[id ?? lastTicket] = .answered(text)
	}

	/// The human closed the window without answering.
	public func dismiss(_ id: PromptId? = nil) {
		outcomes[id ?? lastTicket] = .dismissed
	}
}
