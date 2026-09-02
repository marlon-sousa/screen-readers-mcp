// A hand-written stateful fake for the KeyboardLayout adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/KeyboardLayout.swift.
//
// IT ANSWERS FROM A TABLE A TEST WRITES, AND ITS DEFAULT IS DELIBERATELY NOT
// ANSI. The real seam answers from whatever keyboard the developer is typing on,
// so a test built on it would assert against a Brazilian layout here and an
// American one in CI. More to the point, the property under test is that
// `CGKeystrokePresser` asks the LAYOUT rather than a table of its own -- and a
// fake whose answers matched the US keycodes could not tell a presser that asked
// from one that had the constants hard-coded, which is the exact mistake spec
// 0048 §2.4 exists to prevent.
//
// SO THE DEFAULT TABLE USES OBVIOUSLY INVENTED KEYCODES. If an assertion ever
// passes against a real ANSI value, something is reading a table it should not
// have.
//
// A CHARACTER THAT IS NOT IN THE TABLE IS UNREACHABLE, which is the seam's own
// "this layout has no key for that" -- and the case worth a test of its own,
// because the answer to it must be a named failure with nothing posted.

import VoiceOverBridgeAdapters

public final class FakeKeyboardLayout: KeyboardLayout {
	/// The layout this fake stands for. Mutable, so a test can change layouts
	/// mid-run the way a person switching input sources does.
	public var keys: [Character: LayoutKey]

	public private(set) var asked: [Character] = []

	/// A small invented layout: `l`, `f`, `t` and `4` unshifted, and `$` on the
	/// shifted layer of the same key as `4` -- which is the arrangement a French
	/// layout inverts and the reason the seam reports a layer at all.
	public static let inventedLayout: [Character: LayoutKey] = [
		"l": LayoutKey(keyCode: 201, shifted: false),
		"f": LayoutKey(keyCode: 202, shifted: false),
		"t": LayoutKey(keyCode: 203, shifted: false),
		"4": LayoutKey(keyCode: 204, shifted: false),
		// 13.19's letter: `h` is what an ordinary user presses to move by
		// heading with single-key Quick Nav on, and `kb:h` is how a session
		// says it. Here so the integration test can press the real one.
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

	/// The forward question, answered by INVERTING the same table -- so a test
	/// cannot set up a layout where the two directions disagree, and a presser
	/// that stamped the wrong layer is caught rather than accommodated.
	///
	/// `unstampable` is how a test asks for the layout that will not answer, which
	/// the seam documents as "leave the event as the system built it" rather than
	/// as a failure.
	public var unstampable: Set<UInt16> = []

	public func character(forKeyCode keyCode: UInt16, shifted: Bool) -> String? {
		guard !unstampable.contains(keyCode) else { return nil }
		let found = keys.first { _, key in key.keyCode == keyCode && key.shifted == shifted }
		return found.map { String($0.key) }
	}
}
