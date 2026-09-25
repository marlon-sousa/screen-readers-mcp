// ROLE: adapter implementing the FocusInspector port over the AccessibilityTree, FrontmostApplication and AccessibilityTrust seams.
// BUILT BY: VoiceOverAdapterFactory. USED BY: the GetFocusInfo handler, through the port.
// Measured with VoiceOver on macOS 15.0: the accessibility tree follows the keyboard cursor, while the VoiceOver cursor can move elsewhere after one keystroke (`scripts/voiceover_cursors.sh`).
// Never add a second route as a silent fallback: an answer from a different view is one an agent cannot interpret.
// An empty read is never a reader fault: VoiceOver itself frontmost and a wedged application both return nothing on macOS 15; only a refused channel throws.
// Never compare a string the reader renders: `AXRoleDescription` is localized, so `role` uses `AXRole` and states come from boolean attributes.

import VoiceOverBridgeDomain

public final class VoiceOverFocusInspector: FocusInspector {
	/// `AXTitle` is preferred over `AXDescription`; `AXRoleDescription` is never asked for.
	static let attributes = [
		"AXRole", "AXTitle", "AXDescription", "AXValue", "AXFocused", "AXSelected", "AXEnabled",
	]

	/// A state is emitted only when its attribute is present and equals `reportedWhen`; an absent attribute contributes nothing.
	static let stateFlags: [(attribute: String, reportedWhen: Bool, state: String)] = [
		("AXFocused", true, "focused"),
		("AXSelected", true, "selected"),
		("AXEnabled", false, "disabled"),
	]

	private let tree: any AccessibilityTree
	private let frontmost: any FrontmostApplication
	private let trust: any AccessibilityTrust

	public init(
		tree: any AccessibilityTree,
		frontmost: any FrontmostApplication,
		trust: any AccessibilityTrust
	) {
		self.tree = tree
		self.frontmost = frontmost
		self.trust = trust
	}

	public func focusInfo() throws -> FocusSnapshot {
		let application = frontmost.frontmostApplication()
		let appModule = application?.bundleIdentifier

		// A missing grant is a failure, not an empty answer: every session starts holding it, so a human revoked it, and "nothing focused" would mislead the agent.
		guard trust.isTrusted() else {
			throw FocusError(
				"the focus cannot be read: \(Permission.accessibility.described) Every session of "
				+ "this bridge holds that grant at the handshake, so it has been revoked since this "
				+ "one began.")
		}
		// Nothing frontmost is an answer, not a fault.
		guard let application else { return FocusSnapshot(appModule: appModule) }
		return try treeSnapshot(application, appModule: appModule)
	}

	// -- the accessibility route ------------------------------------------------

	private func treeSnapshot(
		_ application: ApplicationIdentity, appModule: String?
	) throws -> FocusSnapshot {
		let element: [String: AccessibilityValue]?
		do {
			element = try tree.focusedElement(
				pid: application.processIdentifier, attributes: Self.attributes)
		} catch let failure as AccessibilityTreeFailure {
			throw FocusError(
				"the accessibility API would not answer (\(failure.code)): \(failure.description)")
		}
		// Nothing focused is an answer; see the header.
		guard let element else { return FocusSnapshot(appModule: appModule) }

		return FocusSnapshot(
			name: Self.name(from: element),
			role: Self.text(element["AXRole"]) ?? "",
			states: Self.states(from: element),
			value: Self.rendered(element["AXValue"]),
			appModule: appModule
		)
	}

	/// `AXTitle`, else `AXDescription`, else empty: an unlabelled control is an answer.
	static func name(from element: [String: AccessibilityValue]) -> String {
		text(element["AXTitle"]) ?? text(element["AXDescription"]) ?? ""
	}

	static func states(from element: [String: AccessibilityValue]) -> [String] {
		stateFlags.compactMap { flag in
			guard case .flag(let value)? = element[flag.attribute] else { return nil }
			return value == flag.reportedWhen ? flag.state : nil
		}
	}

	static func text(_ value: AccessibilityValue?) -> String? {
		guard case .text(let text)? = value else { return nil }
		return text
	}

	/// Whole numbers render without a decimal point; an attribute that cannot be rendered answers nil.
	static func rendered(_ value: AccessibilityValue?) -> String? {
		switch value {
		case .text(let text):
			return text
		case .flag(let flag):
			return flag ? "true" : "false"
		case .number(let number):
			return number == number.rounded() && abs(number) < 1e15
				? String(Int64(number)) : String(number)
		case .opaque, nil:
			return nil
		}
	}
}
