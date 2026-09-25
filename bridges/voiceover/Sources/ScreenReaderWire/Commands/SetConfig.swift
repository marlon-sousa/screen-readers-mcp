// ROLE: entity, `setConfig`'s params; it answers with ConfigResult, the value read back after the write.

public struct SetConfigParams: Codable, Equatable, Sendable {
	public var keyPath: [String]
	public var value: JSONValue

	public init(keyPath: [String], value: JSONValue) {
		self.keyPath = keyPath
		self.value = value
	}
}
