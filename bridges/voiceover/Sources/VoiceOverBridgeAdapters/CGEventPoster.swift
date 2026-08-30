// ROLE: LEAF adapter -- IMPLEMENTS the EventPoster seam. It builds one keyboard
// event with a Unicode payload and posts it, and that is the whole file.
//
// BUILT BY: Wiring, once per process. USED BY: AccessibilityTextTyper, through
// the seam, never directly.
//
// NO TEST FILE, DELIBERATELY, AND THIS IS THE ONE PLACE IN THIS ENTRY WHERE
// "there is nothing to unit-test" IS ALSO A SAFETY RULE. It makes no decisions:
// the chunking, the ordering and the key-down/key-up pairing are all one layer
// up, against a recording double. And a test that exercised this class would
// type into whatever window the developer had in front of them at that moment --
// so the untestable leaf is also the leaf no test may ever build.
//
// VIRTUAL KEY 0 CARRIES NO MEANING. The keycode is required by the event's shape
// and is overwritten by the Unicode payload, so nothing here maps a character to
// a key and the machine's keyboard layout is irrelevant -- which is
// protocol.md §5's "layout-independent Unicode injection" in one line of code.
//
// `post` REPORTS NOTHING, AND THAT IS THE API RATHER THAN AN OMISSION. Core
// Graphics returns no status: an event from a process without the Accessibility
// grant is dropped by the window server with nothing said anywhere. That is why
// the grant is checked before this file is ever reached -- see the TypeText
// handler, which is the only place in the bridge that asks for it.

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
}
