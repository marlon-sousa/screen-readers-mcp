// ROLE: adapter seam posting one keyboard event, and saying if it could not be built or sent.
// IMPLEMENTED BY: CGEventPoster and FakeEventPoster.
// USED BY: AccessibilityTextTyper and CGKeystrokePresser.
// Modifier transitions are separate events because on macOS 15 a chord posted with flags alone left `CGEventSource.flagsState` reporting Command held, turning later keystrokes into chords.
// No test may post a real event: it types into whatever window the developer has in front.

import CoreGraphics

public struct EventPostingFailure: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol EventPoster: AnyObject {
	/// Cannot report that the text arrived: without the Accessibility grant the window server drops the event silently; throws only when it cannot be built or handed over.
	func post(unicode: String, keyDown: Bool) throws

	/// `characters` is what the active layout produces on the pressed layer, because VoiceOver on macOS 15 matches on the character and a keycode-built event carries the unshifted one.
	/// Nil leaves whatever the system filled in, which is right for a named key; like the Unicode shape, this reports nothing about what happened.
	func post(keyCode: UInt16, flags: CGEventFlags, characters: String?, keyDown: Bool) throws

	/// `keyCode` is the modifier key and `flags` the keyboard state after the transition.
	func postFlagsChanged(keyCode: UInt16, flags: CGEventFlags) throws
}
