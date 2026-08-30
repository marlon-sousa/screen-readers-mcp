// ROLE: entity -- the reader's browse/focus mode, as reported and as requested.
//
// Pure. Carried by StateResult (what the reader is in) and by SetStateParams
// (what a session asks it to be), which is why it is its own file rather than
// living in either.
//
// `none` IS A THIRD ANSWER, NOT AN ABSENT ONE: it is what a reader reports when
// the concept does not apply to what is focused. An Optional would say something
// different -- "the field was not sent" -- and the contract distinguishes them.

public enum BrowseMode: String, Codable, CaseIterable, Sendable {
	case browse
	case focus
	case none
}
