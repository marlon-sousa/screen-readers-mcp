// ROLE: port -- answer "where am I", as a structured snapshot.
// IMPLEMENTED BY: VoiceOverFocusInspector, over three adapter seams; FakeFocusInspector.
// BUILT BY: VoiceOverAdapterFactory.
// USED BY: the GetFocusInfo controller only.
// Nothing here or below it may request a permission: focus only reads whether the Accessibility grant is held.

/// `role` and `states` are the accessibility framework's English constants (`AXButton`), never the reader's localized rendering.
/// A nil `value` or `appModule` is an answer, and the wire keeps the key present.
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

/// Focus that could not be read at all; empty focus is an empty snapshot, never this error.
/// With VoiceOver itself frontmost every read comes back empty, and that is not a dead reader.
public struct FocusError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol FocusInspector: AnyObject {
	func focusInfo() throws -> FocusSnapshot
}
