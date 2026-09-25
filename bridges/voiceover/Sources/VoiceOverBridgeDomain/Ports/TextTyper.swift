// ROLE: port -- insert literal text into whatever holds system focus.
// IMPLEMENTED BY: AccessibilityTextTyper, over the EventPoster seam; FakeTextTyper.
// BUILT BY: VoiceOverAdapterFactory.
// USED BY: the TypeText controller only.
// The text is routed without interpretation, control characters and newlines included; nothing here presses Return.
// A missing Accessibility grant cannot be detected here; see KeyPresser.

public struct TypingError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol TextTyper: AnyObject {
	/// Promises that the keystrokes went out, never that the text arrived unchanged.
	func type(_ text: String) throws
}
