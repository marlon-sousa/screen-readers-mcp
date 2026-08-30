// ROLE: LEAF adapter -- IMPLEMENTS the AccessibilityTree seam. It copies named
// attribute values off the focused element of one application, and that is the
// whole file.
//
// BUILT BY: Wiring, once per process. USED BY: VoiceOverFocusInspector, through
// the seam, never directly.
//
// NO TEST FILE, DELIBERATELY. It makes no decisions: which attributes to ask
// for, which answer wins, what becomes a state and what an empty read means are
// all one layer up, against a dictionary-answering double. What is left here is
// two API calls and a type-id comparison, and the failure mode of getting the
// comparison wrong is `.opaque` -- which the adapter above already treats as
// "there is a value and it is not text".
//
// ============================================================================
// `AXUIElementCreateSystemWide()` FAILS ON THIS MACHINE WITH -25204
// (`kAXErrorCannotComplete`), AND NO PERMISSION FIXES IT.
// ============================================================================
//
// Measured in spec 0047 while prototyping this adapter. It is the obvious first
// thing to reach for -- one element, no pid, "the focused element anywhere" --
// and it does not work: asking the system-wide element for
// `kAXFocusedUIElementAttribute` returns `cannotComplete`, which is NOT
// `kAXErrorAPIDisabled` (-25211) and therefore says nothing about the
// Accessibility grant. Granting more permissions does not change it, and anybody
// who reads the number as a permission problem will spend an evening proving
// that.
//
// SO THE ELEMENT IS ALWAYS A PER-APPLICATION ONE: `AXUIElementCreateApplication`
// with the frontmost pid, which works with the grant and returns
// `kAXErrorAPIDisabled` without it. That is why this seam takes a pid at all,
// and why `FrontmostApplication` is a collaborator of the adapter above rather
// than a convenience.
//
// AND AN EMPTY ANSWER IS NOT A FAULT. `noValue` and `attributeUnsupported` are
// reported as "nothing there" rather than as errors, because that is what an
// application between windows looks like -- and what VoiceOver's own process
// looks like ALWAYS, since it publishes no accessibility tree of its own (spec
// 0047, finding 5).

import ApplicationServices

public final class AXAccessibilityTree: AccessibilityTree {
	public init() {}

	public func focusedElement(pid: Int32, attributes: [String]) throws -> [String: AccessibilityValue]? {
		// PER-APPLICATION, NEVER SYSTEM-WIDE. See the header for the measurement.
		let application = AXUIElementCreateApplication(pid)
		guard let focused = try Self.copy(kAXFocusedUIElementAttribute, from: application) else {
			return nil
		}
		// The focused attribute answers an element; anything else means the tree
		// is not shaped the way the API documents, which is worth saying rather
		// than silently returning nothing.
		guard CFGetTypeID(focused) == AXUIElementGetTypeID() else {
			throw AccessibilityTreeFailure(
				code: 0, description: "the focused attribute did not answer with an element")
		}
		let element = unsafeBitCast(focused, to: AXUIElement.self)

		var values: [String: AccessibilityValue] = [:]
		for attribute in attributes {
			// An attribute the element does not carry is ABSENT from the result,
			// which is how "no value" stays distinguishable from "empty".
			if let value = try Self.copy(attribute, from: element) {
				values[attribute] = Self.rendered(value)
			}
		}
		return values
	}

	/// One `AXUIElementCopyAttributeValue`, with the two "there is nothing there"
	/// outcomes folded into nil.
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

	/// A CoreFoundation value in the closed set the seam carries.
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

	/// The error's own name, in English, so the number travels with something a
	/// human can search for. NOT a classification: what each one MEANS to a
	/// caller is the adapter above's business.
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
