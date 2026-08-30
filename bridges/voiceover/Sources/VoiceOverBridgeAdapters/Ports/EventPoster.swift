// ROLE: adapter seam -- post ONE keyboard event carrying a chunk of literal
// text, and say if it could not be built or sent.
//
// NOT A DOMAIN PORT: the domain has no idea that typing on this platform is a
// synthesized CGEvent with a Unicode payload attached to a virtual key that does
// not exist. This is the seam between two adapters, which is the only way one
// adapter may depend on another (AGENTS.md).
//
// IMPLEMENTED BY: CGEventPoster (the leaf, ~15 lines of Core Graphics) and
// FakeEventPoster (Tests/Fakes), which records what it was handed.
// USED BY: AccessibilityTextTyper, which holds every decision above it.
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
}
