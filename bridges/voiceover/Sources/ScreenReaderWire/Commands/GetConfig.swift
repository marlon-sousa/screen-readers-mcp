// ROLE: entity, `getConfig`'s params and its result, which `setConfig` answers with too.

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
