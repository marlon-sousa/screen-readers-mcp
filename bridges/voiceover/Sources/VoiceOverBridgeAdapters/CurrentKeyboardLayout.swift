// ROLE: LEAF adapter -- IMPLEMENTS the KeyboardLayout seam. It asks Text Input
// Services which keyboard layout is active and UCKeyTranslate what each key
// produces on it, and that is the whole file.
//
// BUILT BY: Wiring, once per process. USED BY: CGKeystrokePresser, through the
// seam, never directly.
//
// NO TEST FILE, DELIBERATELY: it makes no decisions. Which layer a character
// sits on is a FACT it reads back from the system, not a choice; what to do
// about a shifted layer, what to do when nothing produces the character, and how
// the answer becomes an event are all one layer up, against a fake seam. If you
// are tempted to put a decision here, it belongs in CGKeystrokePresser.
//
// THE MAP IS BUILT BACKWARDS, AND THERE IS NO OTHER WAY. macOS answers "what
// does keycode 37 produce?" and never "which key produces `l`?", so the only
// route to the second question is to ask the first for every key and invert the
// answer. 128 keycodes times two layers is 256 UCKeyTranslate calls, which is
// why the result is cached.
//
// IT IS CACHED BY THE INPUT SOURCE'S ID, AND THE ID IS RE-READ EVERY TIME.
// `TISCopyCurrentKeyboardInputSource` is one cheap call; rebuilding the map is
// not. Keying the cache on the id means somebody who switches from ABNT2 to US
// mid-session gets the right keys on the very next press, with no notification
// observer to register, forget to remove, or receive on the wrong thread. The
// cheap call every time is the price of not having a stale map, and it is the
// right trade for a bridge whose sessions outlive a person's attention.
//
// A NON-KEYBOARD INPUT SOURCE HAS NO LAYOUT DATA, and that is the one condition
// this file handles rather than reads. With a Japanese or Chinese input method
// selected, the current source is an input MODE and carries no
// `UnicodeKeyLayoutData`; `TISCopyCurrentKeyboardLayoutInputSource` answers with
// the physical layout underneath it, so that is the fallback. Composed input is
// out of scope either way -- see spec 0048 §6.

import Carbon.HIToolbox
import Foundation

public final class CurrentKeyboardLayout: KeyboardLayout {
	/// The map, and the input source it was built for. Rebuilt when the id moves.
	private var cachedSourceID = ""
	private var cachedKeys: [Character: LayoutKey] = [:]
	private let lock = NSLock()

	public init() {}

	public func key(for character: Character) -> LayoutKey? {
		lock.lock()
		defer { lock.unlock() }
		let sourceID = Self.currentSourceID()
		if sourceID != cachedSourceID || cachedKeys.isEmpty {
			cachedKeys = Self.reverseMap()
			cachedSourceID = sourceID
		}
		return cachedKeys[character]
	}

	/// The forward question, asked of the layout that is active now -- 13.25.
	///
	/// NOT CACHED, and it needs no cache: it is one `UCKeyTranslate` call against
	/// one keycode, where the reverse map above is 256 of them. Asking the live
	/// layout every time is also what keeps it honest for somebody who switched
	/// layouts mid-session, which is the rule this whole class is built on.
	public func character(forKeyCode keyCode: UInt16, shifted: Bool) -> String? {
		guard let layout = Self.layoutData() else { return nil }
		return Self.translate(
			keyCode: keyCode, modifiers: shifted ? UInt32(shiftKey >> 8) : 0, layout: layout)
	}

	// -- the system ------------------------------------------------------------

	/// The active input source's id, or empty if the system will not say.
	private static func currentSourceID() -> String {
		guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
			let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
		else {
			return ""
		}
		return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
	}

	/// Every character the active layout can produce on its two plain layers, and
	/// the key that produces it.
	///
	/// The FIRST keycode to produce a character wins, and the unshifted layer is
	/// walked before the shifted one, so a character reachable both ways is
	/// reported unshifted.
	private static func reverseMap() -> [Character: LayoutKey] {
		guard let layout = layoutData() else { return [:] }
		var map: [Character: LayoutKey] = [:]
		// The shift bit as UCKeyTranslate wants it: the Carbon modifier flags
		// shifted right by 8, which is what every implementation of this technique
		// passes and what the header documents.
		for (shifted, modifiers) in [(false, UInt32(0)), (true, UInt32(shiftKey >> 8))] {
			for keyCode in UInt16(0)...127 {
				guard let produced = translate(keyCode: keyCode, modifiers: modifiers, layout: layout),
					produced.count == 1,
					let character = produced.first,
					!character.isNewline,
					map[character] == nil
				else {
					continue
				}
				map[character] = LayoutKey(keyCode: keyCode, shifted: shifted)
			}
		}
		return map
	}

	/// The active layout's `UCKeyboardLayout`, from the keyboard source if the
	/// current one is an input mode that carries none.
	private static func layoutData() -> CFData? {
		for source in [
			TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
			TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
		] {
			guard let source,
				let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
			else {
				continue
			}
			return Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
		}
		return nil
	}

	/// What one key produces under one modifier state, as a string.
	private static func translate(keyCode: UInt16, modifiers: UInt32, layout: CFData) -> String? {
		guard let bytes = CFDataGetBytePtr(layout) else { return nil }
		var deadKeyState: UInt32 = 0
		var length = 0
		var characters = [UniChar](repeating: 0, count: 8)
		let status = bytes.withMemoryRebound(
			to: UCKeyboardLayout.self, capacity: 1
		) { pointer in
			UCKeyTranslate(
				pointer,
				keyCode,
				UInt16(kUCKeyActionDisplay),
				modifiers,
				UInt32(LMGetKbdType()),
				OptionBits(kUCKeyTranslateNoDeadKeysBit),
				&deadKeyState,
				characters.count,
				&length,
				&characters
			)
		}
		guard status == noErr, length > 0 else { return nil }
		return String(utf16CodeUnits: characters, count: length)
	}
}
