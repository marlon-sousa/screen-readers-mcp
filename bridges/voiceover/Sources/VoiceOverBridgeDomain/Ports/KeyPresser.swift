// ROLE: port -- press one keystroke, possibly several ordinary keys held at once, at the system.
// IMPLEMENTED BY: CGKeystrokePresser, over the KeyboardLayout and EventPoster seams; FakeKeyPresser.
// BUILT BY: VoiceOverAdapterFactory.
// USED BY: the PressGesture handler only.
/// A keystroke that could not be pressed.
public struct KeyPressFailure: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol KeyPresser: AnyObject {
	/// Keys go down in the order given and come up in reverse, even after a partial failure, so no key is left held.
	/// It cannot report that anything happened: without the Accessibility grant the window server drops the event silently.
	func press(_ keystroke: Keystroke) throws
}
