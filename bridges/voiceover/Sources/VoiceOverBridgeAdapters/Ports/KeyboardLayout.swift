// ROLE: adapter seam -- which physical key produces a given character on the
// keyboard layout that is active RIGHT NOW.
//
// NOT A DOMAIN PORT: the domain has a `Keystroke` and no idea that pressing one
// on this platform means finding a virtual keycode for a character. This is the
// seam between two adapters, which is the only way one adapter may depend on
// another (AGENTS.md).
//
// IMPLEMENTED BY: CurrentKeyboardLayout (the leaf, Text Input Services and
// UCKeyTranslate) and FakeKeyboardLayout (Tests/Fakes), which answers from a
// table a test writes.
// USED BY: CGKeystrokePresser, which holds every decision above it.
//
// ============================================================================
// THIS SEAM EXISTS BECAUSE A HARD-CODED KEYCODE TABLE WOULD HAVE SHIPPED.
// ============================================================================
//
// A `CGEvent` carries a virtual keycode, and which keycode produces `l` depends
// on the layout the person is typing on. The maintainer of this repository uses
// a Brazilian keyboard. A table of ANSI constants would compile, pass every test
// its author wrote, read perfectly well in review -- and press the wrong key on
// his machine, which is the exact shape of failure this lane keeps paying for.
// So there is no table in this repository: the LAYOUT answers, or the press
// fails by name (spec 0048 §2.4).
//
// AND THE SEAM REPORTS WHICH LAYER THE CHARACTER SITS ON, which is the one
// design decision in its shape. A layout has an unshifted layer and a shifted
// one, and where a character sits differs between layouts in ways nobody should
// have to know: the digits are unshifted on a Brazilian or an American keyboard
// and SHIFTED on a French AZERTY one, so a seam that answered only "keycode 21"
// would make `command+4` a named failure on a machine where the user presses it
// daily. Reporting the layer keeps the DECISION -- that a shifted layer means a
// `.maskShift` on the event -- above this line, where it is an ordinary unit
// test, and leaves the leaf with nothing to decide.

/// Where a character lives on the active layout.
public struct LayoutKey: Equatable {
	/// The virtual keycode to put in the event.
	public let keyCode: UInt16

	/// Whether the character is on the SHIFTED layer of that key, so the press
	/// needs a Shift it was not asked for.
	public let shifted: Bool

	public init(keyCode: UInt16, shifted: Bool) {
		self.keyCode = keyCode
		self.shifted = shifted
	}
}

public protocol KeyboardLayout: AnyObject {
	/// The key that produces `character` on the layout that is active now, or nil
	/// if this layout has none.
	///
	/// NIL IS AN ANSWER, NOT A FAULT. "This layout has no key that produces `\`"
	/// is something an agent can act on -- try another chord, or ask the human --
	/// and it is the whole reason the return type is optional rather than a
	/// keycode with a plausible default. Pressing something else instead is the
	/// one outcome this seam exists to make impossible.
	func key(for character: Character) -> LayoutKey?
}
