// Hand-written stateful fake for the PromptWindow adapter seam; no test may open a real window.

import VoiceOverBridgeAdapters
import VoiceOverBridgeDomain

public final class FakePromptWindow: PromptWindow {
	public private(set) var opened: [(id: PromptId, prompt: String)] = []
	public private(set) var closed: [PromptId] = []
	private var callbacks: [PromptId: (PromptOutcome) -> Void] = [:]

	public init() {}

	public func open(id: PromptId, prompt: String, onOutcome: @escaping (PromptOutcome) -> Void) {
		opened.append((id, prompt))
		callbacks[id] = onOutcome
	}

	public func close(_ id: PromptId) {
		closed.append(id)
	}

	public func report(_ id: PromptId, _ outcome: PromptOutcome) {
		callbacks[id]?(outcome)
	}
}
