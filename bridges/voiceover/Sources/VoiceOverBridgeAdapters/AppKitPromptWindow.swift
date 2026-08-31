// ROLE: LEAF adapter -- IMPLEMENTS the PromptWindow seam over AppKit. It puts a
// window on the screen and reports what the human did with it; it decides
// nothing else.
//
// BUILT BY: Wiring, once per process. USED BY: AppKitUserPrompter, which holds
// the ticket, the table of answers and every rule about them.
//
// NO TEST FILE, AND HERE THAT IS A HARD RULE RATHER THAN THE USUAL LEAF
// ARGUMENT: a real window needs an NSApplication, takes focus from whatever the
// developer is doing, and announces itself out loud on a machine with a screen
// reader running. The seam above is what lets the prompter's behaviour be tested
// without any of that.
//
// IT MARSHALS TO THE MAIN THREAD ITSELF, in both directions. Every caller here is
// the SESSION thread -- `askUser` runs on it, and so does teardown -- and AppKit
// may only be touched on the main one. Nothing waits: the session thread asks for
// a window and carries on, which is the rule this bridge's UI element lives
// under (spec 0046, part 3, element 5) and the reason `present` can promise not
// to block.
//
// THE WINDOWS DICTIONARY IS TOUCHED ONLY ON THE MAIN THREAD, so it needs no lock
// -- and it needs to exist at all because an NSWindow with nothing holding it is
// deallocated out from under the person reading it.
//
// IT IS DELIBERATELY PLAIN. A label, a text field, two buttons, and the field is
// first responder so a human who cannot see the screen can type and press return
// without hunting for anything. The prompt is also the field's accessibility
// label, so a reader that lands on the field alone still says what is being
// asked.

import AppKit
import VoiceOverBridgeDomain

public final class AppKitPromptWindow: PromptWindow {
	private var panels: [PromptId: PromptPanel] = [:]

	public init() {}

	public func open(id: PromptId, prompt: String, onOutcome: @escaping (PromptOutcome) -> Void) {
		onMain {
			let panel = PromptPanel(prompt: prompt) { [weak self] outcome in
				self?.panels[id] = nil
				onOutcome(outcome)
			}
			self.panels[id] = panel
			panel.show()
		}
	}

	public func close(_ id: PromptId) {
		onMain {
			self.panels[id]?.dismissWithoutReporting()
			self.panels[id] = nil
		}
	}

	/// Run on the main thread, from whichever thread called. `async` even when we
	/// are already on it would be correct too; running inline is what keeps a
	/// close issued from the main thread's own teardown immediate.
	private func onMain(_ work: @escaping () -> Void) {
		if Thread.isMainThread {
			work()
		} else {
			DispatchQueue.main.async(execute: work)
		}
	}
}

/// One question on the screen: the window, its field, and the one report it
/// makes. Private to this file, per the repo's rule that a small helper may
/// share its owner's file.
private final class PromptPanel: NSObject, NSWindowDelegate {
	private let window: NSWindow
	private let field: NSTextField
	private var report: ((PromptOutcome) -> Void)?

	init(prompt: String, onOutcome: @escaping (PromptOutcome) -> Void) {
		report = onOutcome
		window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 420, height: 150),
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: false
		)
		field = NSTextField(string: "")
		super.init()

		window.title = "Screen reader testing"
		window.isReleasedWhenClosed = false
		window.delegate = self
		window.center()

		let label = NSTextField(wrappingLabelWithString: prompt)
		label.frame = NSRect(x: 20, y: 80, width: 380, height: 50)
		field.frame = NSRect(x: 20, y: 48, width: 380, height: 24)
		// So a reader that lands on the field alone still says what is being asked.
		field.setAccessibilityLabel(prompt)
		field.target = self
		field.action = #selector(answer)

		let answerButton = NSButton(title: "Answer", target: self, action: #selector(answer))
		answerButton.frame = NSRect(x: 300, y: 12, width: 100, height: 28)
		answerButton.keyEquivalent = "\r"
		let dismissButton = NSButton(title: "Dismiss", target: self, action: #selector(dismiss))
		dismissButton.frame = NSRect(x: 196, y: 12, width: 100, height: 28)
		dismissButton.keyEquivalent = "\u{1b}"

		window.contentView?.addSubview(label)
		window.contentView?.addSubview(field)
		window.contentView?.addSubview(answerButton)
		window.contentView?.addSubview(dismissButton)
	}

	func show() {
		NSApp.activate(ignoringOtherApps: true)
		window.makeKeyAndOrderFront(nil)
		window.makeFirstResponder(field)
	}

	/// Take the window away without reporting: the bridge asked for this, so the
	/// human did nothing that anybody is waiting to hear about.
	func dismissWithoutReporting() {
		report = nil
		window.close()
	}

	@objc private func answer() {
		finish(.answered(field.stringValue))
	}

	@objc private func dismiss() {
		finish(.dismissed)
	}

	func windowWillClose(_ notification: Notification) {
		// The red button, or a close the bridge did not ask for. Whatever has not
		// been reported yet is a dismissal.
		finish(.dismissed)
	}

	private func finish(_ outcome: PromptOutcome) {
		guard let report else { return }
		self.report = nil
		report(outcome)
		window.close()
	}
}
