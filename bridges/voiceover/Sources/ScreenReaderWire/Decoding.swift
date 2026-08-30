// ROLE: supporting construct -- the one place this binding says what "absent"
// means, for the two kinds of absence the contract distinguishes.
//
// Used by every hand-written `init(from:)` in this module. It exists because
// Swift's own `decodeIfPresent` answers nil to BOTH "the key was not sent" and
// "the key was sent as null", and the Python binding does not: `from_dict`
// applies a dataclass default for a missing key and RAISES for a null in a field
// that is not nullable. Two bindings of one contract that disagree about that
// disagree about which frames are legal, and nothing in a test of either side
// alone would show it.
//
// AMENDMENT TO SPEC 0046's 13.3 LAYOUT, with its why: the spec's file table has
// no entry for this. It is here rather than repeated at ~40 decode sites because
// the rule is subtle enough that repeating it is how one site quietly gets it
// wrong -- and a field that silently defaults instead of failing is exactly the
// fault a wire binding is written to prevent.
//
// The other kind of field -- genuinely nullable, defaulting to null -- keeps
// `decodeIfPresent`, because for those two absences ARE the same answer.

extension KeyedDecodingContainer {
	/// Decode a field that has a default and is NOT nullable: an absent key means
	/// `fallback`, and an explicit null is a fault.
	func decode<Value: Decodable>(
		_ type: Value.Type,
		forKey key: Key,
		orDefault fallback: Value
	) throws -> Value {
		contains(key) ? try decode(type, forKey: key) : fallback
	}
}
