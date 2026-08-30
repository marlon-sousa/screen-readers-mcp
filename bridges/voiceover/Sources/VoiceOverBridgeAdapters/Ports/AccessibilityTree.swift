// ROLE: adapter seam -- read named attributes off whatever holds keyboard focus
// inside one application.
//
// NOT A DOMAIN PORT: the domain has no idea that focus on this platform is an
// `AXUIElement` reached from a pid. This is the seam between two adapters, which
// is the only way one adapter may depend on another (AGENTS.md).
//
// IMPLEMENTED BY: AXAccessibilityTree (the leaf, ~30 lines of
// ApplicationServices) and FakeAccessibilityTree (Tests/Fakes), which answers
// from a table.
// USED BY: VoiceOverFocusInspector, which holds every decision above it.
//
// ONE CALL, AND NO ELEMENT HANDLE CROSSES THIS LINE -- a layout amendment to
// spec 0046's 13.9 table, with its why. The table names the seam as "focused
// element of a pid, and an attribute of an element", which is two calls with an
// opaque element passed between them. That element would have to be an
// `AXUIElement` wearing a disguise: a fake could not construct one, so the seam
// would carry a boxed `AnyObject` and the LEAF would have to cast it back --
// putting a failure case in the file whose entire justification is that it has
// none. Asking for the attributes by name in one call removes the handle, leaves
// the leaf with nothing to decide and nothing to unwrap, and makes the double a
// dictionary. Nothing in this entry walks the tree; the entry that needs to can
// widen this seam then, beside the thing that needs it.
//
// WHICH ATTRIBUTES, AND WHAT THEY MEAN, IS THE ADAPTER ABOVE'S BUSINESS. This
// seam fetches names it is given and renders whatever comes back; the list, the
// order they are preferred in, and how they become `name`/`role`/`states`/
// `value` are decisions, and decisions live one layer up where a unit test can
// reach them.

/// One attribute's value, in the few shapes this bridge renders.
///
/// A CLOSED SET, because the alternative is a leaf that decides how to describe
/// an arbitrary CoreFoundation object -- which is a decision, in the one file
/// that may not make any. An attribute this bridge cannot render is reported as
/// `.opaque`: it EXISTS and its content is not text, which is a different fact
/// from the attribute being absent (absent is a missing key).
public enum AccessibilityValue: Equatable, Sendable {
	case text(String)
	case flag(Bool)
	case number(Double)
	case opaque
}

/// The accessibility API refused to answer.
///
/// The NUMBER is the contract, exactly as it is for `AppleScriptError` and for
/// the same reason: `AXError`'s numbers are stable and any message about them is
/// this bridge's own prose. Nothing above may branch on the description.
public struct AccessibilityTreeFailure: Error, Equatable, CustomStringConvertible {
	public let code: Int
	public let description: String

	public init(code: Int, description: String) {
		self.code = code
		self.description = description
	}
}

public protocol AccessibilityTree: AnyObject {
	/// The values of `attributes` on whatever holds keyboard focus inside the
	/// application `pid`.
	///
	/// NIL MEANS NOTHING IS FOCUSED THERE, and it is an ANSWER rather than a
	/// failure -- an application between windows, a process that publishes no
	/// tree at all (which is what VoiceOver itself does; spec 0047's finding 5).
	/// An attribute the element does not carry is simply absent from the
	/// dictionary, which is how "no value" stays distinguishable from "empty".
	func focusedElement(pid: Int32, attributes: [String]) throws -> [String: AccessibilityValue]?
}
