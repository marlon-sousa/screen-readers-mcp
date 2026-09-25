// ROLE: entity, `echo`'s params and result.

public struct EchoParams: Codable, Equatable, Sendable {
	public var payload: JSONValue

	public init(payload: JSONValue) {
		self.payload = payload
	}
}

public struct EchoResult: Codable, Equatable, Sendable {
	public var payload: JSONValue

	public init(payload: JSONValue) {
		self.payload = payload
	}
}
