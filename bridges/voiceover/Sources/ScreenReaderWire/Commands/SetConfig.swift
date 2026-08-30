// ROLE: entity -- `setConfig`'s params. It answers with ConfigResult, which
// lives with `getConfig` in GetConfig.swift because that is the command named
// after it.
//
// Pure. The result is the value AFTER the write, read back rather than echoed,
// so a reader that coerced or rejected what it was given says so in the answer.

public struct SetConfigParams: Codable, Equatable, Sendable {
	public var keyPath: [String]
	public var value: JSONValue

	public init(keyPath: [String], value: JSONValue) {
		self.keyPath = keyPath
		self.value = value
	}
}
