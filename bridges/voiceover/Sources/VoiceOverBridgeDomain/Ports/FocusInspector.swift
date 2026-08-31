// ROLE: port -- answer "where am I", as a structured snapshot.
//
// IMPLEMENTED BY: VoiceOverFocusInspector (adapters), over three adapter seams;
// FakeFocusInspector (Tests/Fakes).
// BUILT BY: VoiceOverAdapterFactory. USED BY: the GetFocusInfo controller, and
// nothing else.
// OWNS: `FocusSnapshot`, its DTO, and `FocusError`, its signalling type -- both
// in this file, per the repo's rule that a port's types live with the port.
//
// THE DOMAIN DOES NOT KNOW THAT FOCUS HAS TWO ROUTES, AND THAT IS DELIBERATE.
// On this reader the answer comes from the accessibility tree when this process
// holds the Accessibility grant and from the VoiceOver cursor when it does not
// (spec 0046's 13.9 section) -- but "which route" is a DECISION, decisions live
// in the upper adapter, and a permission is a macOS fact that has no business in
// a port's signature. So `focusInfo()` takes nothing and the adapter chooses.
// The layout amendment that settles this, with the alternative it was chosen
// over, is recorded in spec 0046's 13.9 section.
//
// NOTHING HERE REQUESTS A PERMISSION, AND NOTHING BELOW IT MAY EITHER. 13.8's
// lever is that the Accessibility grant is requested from ONE place, the
// TypeText controller, on a `typeText`. Focus READS whether the grant is held --
// a question that asks nobody anything and raises no dialog -- and uses one that
// typing already obtained. A session that only presses commands and reads
// speech, focus included, never triggers a request.

/// What is focused, in the wire's own vocabulary (protocol.md §5).
///
/// `role` and `states` are reader-specific strings that pass through opaquely,
/// and on this reader they are the accessibility framework's own English
/// CONSTANTS (`AXButton`, and flags derived from `AXFocused`/`AXSelected`/
/// `AXEnabled`) rather than anything the reader renders. That is the lane's
/// no-reader-strings rule in its focus instance: roles and structure survive
/// translation, and `AXRoleDescription` -- which is what a localized machine
/// would answer here -- does not.
///
/// `value` and `appModule` ARE OPTIONAL AND THE WIRE KEEPS THEM PRESENT: "the
/// element has no value" is an answer, and "the frame forgot the field" is a
/// fault. See `FocusInfoResult`, which encodes them by hand for that reason.
public struct FocusSnapshot: Equatable, Sendable {
	public let name: String
	public let role: String
	public let states: [String]
	public let value: String?
	public let appModule: String?

	public init(
		name: String = "",
		role: String = "",
		states: [String] = [],
		value: String? = nil,
		appModule: String? = nil
	) {
		self.name = name
		self.role = role
		self.states = states
		self.value = value
		self.appModule = appModule
	}
}

/// Focus that could not be read at all.
///
/// A struct rather than an enum, shaped like `TypingError` and for the same
/// reason: there is exactly one thing to say -- the question could not be put --
/// and its own type rather than the command layer's `CommandError`, because a
/// port may not depend on a controller.
///
/// NOTHING THAT IS MERELY EMPTY THROWS THIS. Nothing focused, an element with no
/// title, a VoiceOver cursor sitting on a process that publishes no tree: each
/// is an ANSWER, and each is reported as an empty snapshot. Spec 0047's finding
/// 5 is why that distinction is a rule rather than a preference -- with
/// VoiceOver itself frontmost every read comes back empty and looks exactly like
/// a dead reader, and it is not one.
public struct FocusError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol FocusInspector: AnyObject {
	/// What holds focus right now.
	///
	/// AN EMPTY SNAPSHOT IS A SUCCESS, not a failure: an agent checks for "no
	/// focus" with the same assertion it uses for "a button is focused". Lane 1's
	/// `FocusInspector` makes the same promise, in the same words.
	func focusInfo() throws -> FocusSnapshot
}
