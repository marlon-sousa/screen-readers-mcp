// ROLE: port -- insert literal text into whatever holds system focus.
//
// IMPLEMENTED BY: AccessibilityTextTyper (adapters), over the EventPoster seam;
// FakeTextTyper (Tests/Fakes).
// BUILT BY: VoiceOverAdapterFactory. USED BY: the TypeText controller, and
// nothing else -- pressing one of the reader's own commands is a DIFFERENT port
// (GestureSender) because it costs a different permission, and that separation
// is the entry's whole design. See PermissionBroker.
//
// TYPING IS NOT A GESTURE ON THIS READER. A gesture here is an English command
// name the reader dispatches itself; literal text cannot come out of a command
// table, so it is synthesized as input events and reaches the focused
// APPLICATION rather than the reader. protocol.md §5: the text is routed without
// interpretation, control characters and newlines included -- nothing here
// presses Return, and nothing here submits anything. An agent composes that from
// `typeText` and `pressGesture`.
//
// THIS PORT CANNOT REPORT A MISSING ACCESSIBILITY GRANT, AND DOES NOT PRETEND
// TO. An event posted by an untrusted process is dropped by the window server;
// `CGEvent.post` returns nothing, so a dropped event and a delivered one are the
// same observable from here. That is exactly why the grant is checked through
// PermissionBroker BEFORE anything is posted, and why `TypingError` has no
// `accessibilityNotGranted` case -- a layout amendment to spec 0046's 13.8
// table, with its why. A case that nothing can throw would read to whoever adds
// the next adapter as a detection this bridge performs.

/// Text that could not be typed.
///
/// A struct rather than an enum because there is exactly one thing to say: the
/// events could not be built or posted at all. Shaped like `AdapterFactoryError`
/// for the same reason -- its own type rather than the command layer's
/// `CommandError`, because a port may not depend on a controller.
public struct TypingError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol TextTyper: AnyObject {
	/// Insert `text` at the focused control, blocking until every event has been
	/// posted.
	///
	/// WHAT IT PROMISES IS THAT THE KEYSTROKES WENT OUT -- never that the text
	/// arrived, and never that it arrived unchanged. See
	/// `AccessibilityTextTyper`'s header for the measurement that makes that
	/// distinction load-bearing.
	func type(_ text: String) throws
}
