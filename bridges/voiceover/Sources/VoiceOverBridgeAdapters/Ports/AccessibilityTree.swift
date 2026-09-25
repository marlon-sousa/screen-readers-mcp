// ROLE: adapter seam reading named attributes off whatever holds keyboard focus inside one application.
// IMPLEMENTED BY: AXAccessibilityTree and FakeAccessibilityTree.
// USED BY: VoiceOverFocusInspector, which holds every decision above it.

/// An attribute that exists but is not text, a number or a flag is `.opaque`; an absent attribute is a missing key.
public enum AccessibilityValue: Equatable, Sendable {
	case text(String)
	case flag(Bool)
	case number(Double)
	case opaque
}

/// Callers branch on `code`, an `AXError` number, never on the description.
public struct AccessibilityTreeFailure: Error, Equatable, CustomStringConvertible {
	public let code: Int
	public let description: String

	public init(code: Int, description: String) {
		self.code = code
		self.description = description
	}
}

public protocol AccessibilityTree: AnyObject {
	/// Nil means nothing is focused in `pid`, an answer rather than a failure; VoiceOver itself publishes no tree.
	/// An attribute the element lacks is absent from the dictionary.
	func focusedElement(pid: Int32, attributes: [String]) throws -> [String: AccessibilityValue]?
}
