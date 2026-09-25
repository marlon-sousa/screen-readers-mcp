// ROLE: leaf adapter that implements the PromptWindow seam over AppKit.
// BUILT BY: Wiring, once per process.
// USED BY: AppKitUserPrompter, which holds the ticket and every rule about answers.
// Never build it in a test: a real window takes focus and announces itself on a machine running a reader.
// Callers are on the session thread; it marshals to the main thread in both directions and never waits.
// `panels` is touched only on the main thread, and it keeps each window alive while a person reads it.

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

	/// Inline when already on the main thread, so a close from the main thread's own teardown is immediate.
	private func onMain(_ work: @escaping () -> Void) {
		if Thread.isMainThread {
			work()
		} else {
			DispatchQueue.main.async(execute: work)
		}
	}
}

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

	/// No report: the bridge asked for this, so nobody is waiting on the human.
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
		// Whatever has not been reported yet is a dismissal.
		finish(.dismissed)
	}

	private func finish(_ outcome: PromptOutcome) {
		guard let report else { return }
		self.report = nil
		report(outcome)
		window.close()
	}
}
