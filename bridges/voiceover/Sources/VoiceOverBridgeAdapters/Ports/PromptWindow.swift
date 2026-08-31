// ROLE: adapter seam -- put a question on the screen, and say when it is
// answered.
//
// NOT A DOMAIN PORT: the domain asks for a human to be asked something
// (`UserPrompter`) and knows nothing about windows, text fields or buttons.
//
// IMPLEMENTED BY: AppKitPromptWindow (a leaf) and FakePromptWindow (Tests/Fakes).
// USED BY: AppKitUserPrompter, which holds every decision -- minting the ticket,
// remembering the answer until somebody polls for it, and refusing to record a
// second outcome for a window that already ended.
//
// THE SEAM EXISTS BECAUSE NO TEST MAY OPEN A WINDOW. A real one needs an
// NSApplication, steals focus from whatever the developer is doing, and on a
// machine with a screen reader running announces itself out loud -- so the whole
// of the prompter's behaviour is exercised against a fake, and what is left
// below this line makes no decisions at all.
//
// THE OUTCOME ARRIVES ON THE MAIN THREAD, because AppKit's does. The prompter
// above is what makes that safe to read from the session thread; nothing here
// may assume which thread called it either, which is why the implementation
// marshals rather than asserting.

import VoiceOverBridgeDomain

public protocol PromptWindow: AnyObject {
	/// Show `prompt` and report the outcome EXACTLY ONCE. Returns immediately:
	/// the window is asked for, not waited on.
	func open(id: PromptId, prompt: String, onOutcome: @escaping (PromptOutcome) -> Void)

	/// Take the window away. Idempotent, and safe for an id that was never opened
	/// or has already ended -- both happen on the ordinary paths, because the
	/// prompter cancels every prompt it closes whether the human ended it or not.
	func close(_ id: PromptId)
}
