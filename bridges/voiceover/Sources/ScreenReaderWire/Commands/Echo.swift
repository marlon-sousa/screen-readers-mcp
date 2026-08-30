// ROLE: entity -- `echo`'s params and result.
//
// Pure. Built by the Echo handler (entry 13.4). The payload is an open value in
// both directions on purpose: echo exists to prove a session can carry a frame
// back unchanged, so constraining what it may carry would test something else.

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
