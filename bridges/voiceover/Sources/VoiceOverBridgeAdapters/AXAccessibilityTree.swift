// ROLE: leaf adapter that implements the AccessibilityTree seam, copying attributes off an app's focused element.
// BUILT BY: Wiring, once per process.
// USED BY: VoiceOverFocusInspector, through the seam.
// The system-wide element answers the focused-element attribute with -25204 (kAXErrorCannotComplete)
// whatever the grant, so the element is always per-application; that error is not a permission problem.
// `noValue` and `attributeUnsupported` mean nothing is there, which VoiceOver's own process always answers.

import ApplicationServices

public final class AXAccessibilityTree: AccessibilityTree {
	public init() {}

	public func focusedElement(pid: Int32, attributes: [String]) throws -> [String: AccessibilityValue]? {
		let application = AXUIElementCreateApplication(pid)
		guard let focused = try Self.copy(kAXFocusedUIElementAttribute, from: application) else {
			return nil
		}
		guard CFGetTypeID(focused) == AXUIElementGetTypeID() else {
			throw AccessibilityTreeFailure(
				code: 0, description: "the focused attribute did not answer with an element")
		}
		let element = unsafeBitCast(focused, to: AXUIElement.self)

		var values: [String: AccessibilityValue] = [:]
		for attribute in attributes {
			// An attribute the element does not carry is absent, so "no value" stays distinct from "empty".
			if let value = try Self.copy(attribute, from: element) {
				values[attribute] = Self.rendered(value)
			}
		}
		return values
	}

	private static func copy(_ attribute: String, from element: AXUIElement) throws -> CFTypeRef? {
		var value: CFTypeRef?
		let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
		switch status {
		case .success:
			return value
		case .noValue, .attributeUnsupported:
			return nil
		default:
			throw AccessibilityTreeFailure(code: Int(status.rawValue), description: describe(status))
		}
	}

	private static func rendered(_ value: CFTypeRef) -> AccessibilityValue {
		let type = CFGetTypeID(value)
		if type == CFStringGetTypeID() {
			return .text(unsafeBitCast(value, to: CFString.self) as String)
		}
		if type == CFBooleanGetTypeID() {
			return .flag(CFBooleanGetValue(unsafeBitCast(value, to: CFBoolean.self)))
		}
		if type == CFNumberGetTypeID() {
			var number = 0.0
			CFNumberGetValue(unsafeBitCast(value, to: CFNumber.self), .doubleType, &number)
			return .number(number)
		}
		return .opaque
	}

	private static func describe(_ status: AXError) -> String {
		switch status {
		case .apiDisabled: return "apiDisabled -- this process is not trusted for accessibility"
		case .cannotComplete: return "cannotComplete -- the application did not answer"
		case .invalidUIElement: return "invalidUIElement -- the element is gone"
		case .notImplemented: return "notImplemented -- the application does not answer this API"
		default: return "AXError \(status.rawValue)"
		}
	}
}
