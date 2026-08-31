// A hand-written stateful fake for the PromptWindow adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/PromptWindow.swift.
//
// NO TEST MAY OPEN A WINDOW. This is what AppKitUserPrompter is exercised
// against, and it keeps each id's callback so a test can be the human: report an
// answer, report a dismissal, or report twice -- which is the sequence the
// prompter's "first outcome wins" rule exists for.

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

	/// Stand in for the person, from whichever thread the test likes -- which is
	/// the point: the real one calls back on AppKit's main thread, at a moment
	/// nothing in the bridge controls.
	public func report(_ id: PromptId, _ outcome: PromptOutcome) {
		callbacks[id]?(outcome)
	}
}
