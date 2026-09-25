// ROLE: supporting construct that says what "absent" means for every hand-written `init(from:)` here.

extension KeyedDecodingContainer {
	/// An absent key means `fallback` and an explicit null is a fault, as in the Python binding.
	func decode<Value: Decodable>(
		_ type: Value.Type,
		forKey key: Key,
		orDefault fallback: Value
	) throws -> Value {
		contains(key) ? try decode(type, forKey: key) : fallback
	}
}
