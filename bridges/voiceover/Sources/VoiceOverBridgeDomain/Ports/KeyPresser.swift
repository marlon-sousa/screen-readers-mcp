// ROLE: port -- press one keystroke at the SYSTEM -- which since 13.22 may hold
// SEVERAL ordinary keys down at once -- and say what went wrong in a vocabulary
// the controller can act on.
//
// IMPLEMENTED BY: CGKeystrokePresser (adapters), over the KeyboardLayout and
// EventPoster seams; FakeKeyPresser (Tests/Fakes).
// BUILT BY: VoiceOverAdapterFactory. USED BY: the PressGesture handler, and by
// nothing else.
//
// IT IS A THIRD INPUT PORT, BESIDE THE GESTURE SENDER AND THE TEXT TYPER, and
// the three are separate because they are three different acts on this platform:
//
//  * `GestureSender` dispatches one of the READER's commands, over an AppleEvent.
//    It costs Automation and no Accessibility grant.
//  * `TextTyper` injects literal CHARACTERS with a Unicode payload, layout-free.
//    It costs Accessibility.
//  * this port presses a KEY with modifiers held, which is neither: it needs a
//    virtual keycode, so it needs the machine's active layout, and it costs
//    Accessibility exactly as typing does.
//
// A METHOD ON THE TYPER WAS THE OBVIOUS ALTERNATIVE AND IS WRONG. `TextTyper`
// promises layout independence -- "the same characters on a Dvorak or an ABNT2
// keyboard as on a US one" -- and a chord cannot keep that promise: Command-L is
// a KEY, in a place that differs between layouts, and the whole difficulty of
// this port is that it has to ask which place. Folding the two together would
// have put a layout question inside the one adapter whose header says the layout
// is irrelevant.
//
// THE DOMAIN KNOWS NOTHING ABOUT KEYCODES OR FLAGS, and this signature is where
// that is enforced: it takes the `Keystroke` entity and gets back either a press
// or a named failure. What a `CGEvent` is, which bit means Command, and how a
// character is looked up in the active layout are all below this line.
//
// THE SIGNATURE DID NOT CHANGE FOR 13.22, and that is the entity earning its
// keep: `leftArrow+rightArrow` is still ONE keystroke, so it is still one call.
// What the adapter must do with it did change -- every key down in order, every
// key up in reverse, in a `defer` -- and that is stated on `press` below.

/// A keystroke that could not be pressed.
///
/// Its own type rather than the command layer's `CommandError`, because a port
/// may not depend on a controller. The PressGesture handler translates it.
///
/// ONE CASE AND NOT THREE, unlike `GestureError`, because the recoveries do not
/// differ enough to be worth naming apart: everything that can go wrong here is
/// "this key could not be produced on this machine", and the adapter's message
/// says which of them it was. The one distinction that DOES matter -- a
/// character the active layout has no key for -- is a sentence an agent can act
/// on rather than a case it should switch on.
public struct KeyPressFailure: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol KeyPresser: AnyObject {
	/// Press and release `keystroke`, with its modifiers held for both halves.
	///
	/// ITS KEYS GO DOWN IN THE ORDER GIVEN AND COME UP IN REVERSE, so that a
	/// chord the reader detects by simultaneity -- Left and Right together, which
	/// is arrow-key Quick Nav -- is really simultaneous, and so that a press that
	/// fails partway cannot leave an ordinary key held down. A stuck letter is
	/// quieter than a stuck Command and just as bad: every keystroke afterwards
	/// repeats it.
	///
	/// IT CANNOT REPORT THAT ANYTHING HAPPENED, and an implementation must not
	/// pretend otherwise: an event posted by a process without the Accessibility
	/// grant is dropped by the window server with no error anywhere, and an
	/// application that ignores the chord looks identical to one that acted on it.
	/// That is why the grant is checked BEFORE this port is reached, and why a
	/// check that needs to know what a chord did asks the application or the
	/// reader -- the same rule `AccessibilityTextTyper`'s header states for text.
	func press(_ keystroke: Keystroke) throws
}
