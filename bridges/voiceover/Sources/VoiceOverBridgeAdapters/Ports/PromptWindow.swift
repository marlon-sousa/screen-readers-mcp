// ROLE: adapter seam that puts a question on screen and says when it is answered.
// IMPLEMENTED BY: AppKitPromptWindow and FakePromptWindow.
// USED BY: AppKitUserPrompter, which holds every decision.
// No test may open a real window: it steals focus, and a running screen reader announces it.
// The outcome arrives on the main thread and callers may be on any thread, so implementations marshal rather than assert.

import VoiceOverBridgeDomain

public protocol PromptWindow: AnyObject {
	/// Reports the outcome exactly once, and returns without waiting for the window.
	func open(id: PromptId, prompt: String, onOutcome: @escaping (PromptOutcome) -> Void)

	/// Idempotent, and safe for an id never opened or already ended, which the ordinary paths produce.
	func close(_ id: PromptId)
}
