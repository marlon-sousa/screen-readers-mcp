// Hand-written stateful fake for the KeyboardLayout adapter seam.
// The default keycodes are invented, so a presser with hard-coded ANSI constants fails against it.

import VoiceOverBridgeAdapters

public final class FakeKeyboardLayout: KeyboardLayout {
	public var keys: [Character: LayoutKey]

	public private(set) var asked: [Character] = []

	public static let inventedLayout: [Character: LayoutKey] = [
		"l": LayoutKey(keyCode: 201, shifted: false),
		"f": LayoutKey(keyCode: 202, shifted: false),
		"t": LayoutKey(keyCode: 203, shifted: false),
		"4": LayoutKey(keyCode: 204, shifted: false),
		"h": LayoutKey(keyCode: 205, shifted: false),
		"$": LayoutKey(keyCode: 204, shifted: true),
	]

	public init(keys: [Character: LayoutKey] = FakeKeyboardLayout.inventedLayout) {
		self.keys = keys
	}

	public func key(for character: Character) -> LayoutKey? {
		asked.append(character)
		return keys[character]
	}

	public var unstampable: Set<UInt16> = []

	public func character(forKeyCode keyCode: UInt16, shifted: Bool) -> String? {
		guard !unstampable.contains(keyCode) else { return nil }
		let found = keys.first { _, key in key.keyCode == keyCode && key.shifted == shifted }
		return found.map { String($0.key) }
	}
}
