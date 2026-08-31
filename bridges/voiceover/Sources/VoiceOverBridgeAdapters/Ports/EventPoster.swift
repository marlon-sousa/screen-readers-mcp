// ROLE: adapter seam -- post ONE keyboard event, and say if it could not be
// built or sent.
//
// NOT A DOMAIN PORT: the domain has no idea that input on this platform is a
// synthesized CGEvent. This is the seam between two adapters, which is the only
// way one adapter may depend on another (AGENTS.md).
//
// IMPLEMENTED BY: CGEventPoster (the leaf, Core Graphics and nothing else) and
// FakeEventPoster (Tests/Fakes), which records what it was handed.
// USED BY: AccessibilityTextTyper and CGKeystrokePresser, each holding every
// decision above it.
//
// THREE SHAPES, BECAUSE THEY ARE THREE DIFFERENT EVENTS. Typing attaches a
// UNICODE PAYLOAD to a virtual key that means nothing, which is how a character
// arrives whatever the layout; a chord presses a real KEY, which is how
// Command-L arrives and is the one thing the payload route cannot do; and a
// MODIFIER TRANSITION is a `flagsChanged` event, which is neither. Collapsing
// them into one call taking optional everything would have hidden those
// differences behind a signature -- and the first difference is exactly what
// board entry 13.17 exists to record, since the bridge spent four entries with
// the payload shape and no key shape while its documentation described the gap
// as a limit of the platform (spec 0048 §1.1).
//
// THE THIRD SHAPE WAS ADDED AFTER A MEASUREMENT, NOT BY DESIGN. Spec 0048 §2.5
// declined separate modifier events in v1 -- flags on the key event are what menu
// shortcuts respond to, and the chord DOES arrive that way. What it does not do
// is put the modifier back: measured live on 2026-08-31, one `command+l` sent
// with flags alone left `CGEventSource.flagsState` reporting **Command held**,
// which turned every subsequent keystroke on the machine into a chord and made
// `typeText` silently type nothing. A latched modifier on somebody's own keyboard
// is not an app-compatibility nicety, so v1 posts the transitions.
//
// WHAT THE SPLIT BUYS, AND IT IS THE REASON THIS SEAM IS SHAPED PER EVENT RATHER
// THAN PER STRING. Everything that could be got wrong about typing is a decision
// about how a string becomes a SEQUENCE of these calls -- how it is chunked, in
// what order, and what a key-down owes a key-up. Above this line all of that is
// an ordinary unit test against a recording double; below it there is one call
// to Core Graphics and nothing to decide. A seam that took the whole string
// would have moved the chunking into the untestable half, which is precisely the
// mistake the layering rule exists to prevent.
//
// AND NO TEST MAY POST A REAL EVENT. `Tests/Fakes/Support/ReaderEdge.swift`
// exists because building the REAL provider lifecycle in a test would change the
// developer's own voice; this is worse, because a real CGEvent types into
// whatever window the developer has in front of them at that moment. The fake is
// not a convenience here, it is the rule.

import CoreGraphics

/// An event that could not be built or posted.
///
/// Its own type rather than the domain's `TypingError`, for the same reason
/// `AppleScriptError` is not `GestureError`: a seam between two adapters owns
/// its own vocabulary, and the adapter above translates.
public struct EventPostingFailure: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol EventPoster: AnyObject {
	/// Post one keyboard event carrying `unicode` as its payload.
	///
	/// `keyDown` says which half of the keystroke this is. Both halves carry the
	/// same payload -- see `AccessibilityTextTyper`, which decides that and says
	/// why.
	///
	/// IT CANNOT REPORT THAT THE TEXT ARRIVED, and an implementation must not
	/// pretend otherwise: an event posted by a process without the Accessibility
	/// grant is dropped by the window server with no error anywhere. Throwing is
	/// for an event that could not be BUILT or handed over at all.
	func post(unicode: String, keyDown: Bool) throws

	/// Post one keyboard event for `keyCode`, with `flags` held.
	///
	/// `keyDown` says which half of the keystroke this is; both halves carry the
	/// same flags -- see `CGKeystrokePresser`, which decides that and says why.
	///
	/// IT REPORTS NOTHING ABOUT WHAT HAPPENED, for the same reason the Unicode
	/// shape does not: an event posted without the Accessibility grant is dropped
	/// by the window server with no error anywhere, and an application that
	/// ignores a chord is indistinguishable from here from one that acted on it.
	/// Throwing is for an event that could not be BUILT or handed over at all.
	func post(keyCode: UInt16, flags: CGEventFlags, keyDown: Bool) throws

	/// Post one modifier transition: `keyCode` is the modifier key, and `flags` is
	/// the state the keyboard is in AFTER it.
	///
	/// A `flagsChanged` event has no notion of down or up -- what it carries is the
	/// resulting state, so pressing Command is a transition to `[.maskCommand]` and
	/// releasing it is a transition to `[]`. Which transitions to post, and in what
	/// order, is `CGKeystrokePresser`'s decision and not this seam's.
	func postFlagsChanged(keyCode: UInt16, flags: CGEventFlags) throws
}
