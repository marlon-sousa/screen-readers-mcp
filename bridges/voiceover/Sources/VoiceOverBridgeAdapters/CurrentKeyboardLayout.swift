// ROLE: leaf adapter implementing the KeyboardLayout seam through Text Input Services and UCKeyTranslate.
// BUILT BY: Wiring, once per process.
// USED BY: CGKeystrokePresser, through the seam.

import Carbon.HIToolbox
import Foundation

public final class CurrentKeyboardLayout: KeyboardLayout {
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

	public func character(forKeyCode keyCode: UInt16, shifted: Bool) -> String? {
		guard let layout = Self.layoutData() else { return nil }
		return Self.translate(
			keyCode: keyCode, modifiers: shifted ? UInt32(shiftKey >> 8) : 0, layout: layout)
	}

	/// The active input source's id, or empty if the system will not say.
	private static func currentSourceID() -> String {
		guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
			let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
		else {
			return ""
		}
		return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
	}

	/// The first keycode to produce a character wins, unshifted layer first.
	private static func reverseMap() -> [Character: LayoutKey] {
		guard let layout = layoutData() else { return [:] }
		var map: [Character: LayoutKey] = [:]
		// UCKeyTranslate takes the Carbon modifier flags shifted right by 8.
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

	/// An input mode such as a Japanese or Chinese one carries no layout data, so the keyboard layout source is asked first.
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
