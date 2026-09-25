// ROLE: leaf adapter that implements the EventPoster seam: it builds one keyboard event and posts it.
// BUILT BY: Wiring, once per process.
// USED BY: AccessibilityTextTyper and CGKeystrokePresser, through the seam.
// Never build it in a test: it types into whatever window the developer has in front of them.
// Core Graphics reports nothing: an event from a process without the Accessibility grant is dropped
// silently, so the grant must be checked before this is reached.

import CoreGraphics
import Foundation

public final class CGEventPoster: EventPoster {
	public init() {}

	public func post(unicode: String, keyDown: Bool) throws {
		guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: keyDown) else {
			throw EventPostingFailure("the system would not create a keyboard event")
		}
		let units = Array(unicode.utf16)
		event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
		event.post(tap: .cghidEventTap)
	}

	/// The characters are stamped after the flags and before the post; none leaves the unshifted character
	/// the system filled in.
	public func post(
		keyCode: UInt16, flags: CGEventFlags, characters: String?, keyDown: Bool
	) throws {
		guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown)
		else {
			throw EventPostingFailure("the system would not create a keyboard event")
		}
		event.flags = flags
		if let characters {
			let units = Array(characters.utf16)
			event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
		}
		event.post(tap: .cghidEventTap)
	}

	/// Built as a key event and retyped, because Core Graphics offers no constructor for a `flagsChanged` event.
	public func postFlagsChanged(keyCode: UInt16, flags: CGEventFlags) throws {
		guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
		else {
			throw EventPostingFailure("the system would not create a modifier event")
		}
		event.type = .flagsChanged
		event.flags = flags
		event.post(tap: .cghidEventTap)
	}
}
