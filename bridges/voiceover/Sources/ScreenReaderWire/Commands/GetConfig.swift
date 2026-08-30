// ROLE: entity -- `getConfig`'s params and its result, which `setConfig`
// answers with too.
//
// Pure. `keyPath` is a path INTO the reader's own configuration tree and `value`
// is whatever it holds -- both deliberately untyped by the contract, because a
// reader's settings are its own vocabulary and the chassis must not interpret
// them (spec 0005). That is why `value` is an open JSON value rather than a
// String.

public struct GetConfigParams: Codable, Equatable, Sendable {
	public var keyPath: [String]

	public init(keyPath: [String]) {
		self.keyPath = keyPath
	}
}

public struct ConfigResult: Codable, Equatable, Sendable {
	public var value: JSONValue

	public init(value: JSONValue) {
		self.value = value
	}
}
