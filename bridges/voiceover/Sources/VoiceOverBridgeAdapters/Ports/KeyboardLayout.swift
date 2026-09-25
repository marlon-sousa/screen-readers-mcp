// ROLE: adapter seam naming which physical key produces a character on the keyboard layout active now.
// IMPLEMENTED BY: CurrentKeyboardLayout and FakeKeyboardLayout.
// USED BY: CGKeystrokePresser.
// Never hard-code a keycode table: which keycode produces a character depends on the active layout, and on French AZERTY the digits are on the shifted layer.

public struct LayoutKey: Equatable {
	public let keyCode: UInt16

	public let shifted: Bool

	public init(keyCode: UInt16, shifted: Bool) {
		self.keyCode = keyCode
		self.shifted = shifted
	}
}

public protocol KeyboardLayout: AnyObject {
	/// The key producing `character` now, or nil if the layout has none, which is an answer and never a cue to press something else.
	func key(for character: Character) -> LayoutKey?

	/// What `keyCode` produces on the chosen layer; nil means do not stamp, and the event keeps whatever the system filled in (see `EventPoster`).
	func character(forKeyCode keyCode: UInt16, shifted: Bool) -> String?
}
