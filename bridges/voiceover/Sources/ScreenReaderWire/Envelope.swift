// ROLE: entity, the request and response frames every session exchanges, and the error a response may carry.
// `cmd` is a raw string, so an unknown command reaches the registry as data instead of failing to decode.
// The Python bridge's error frame carries both keys, `{"id":7,"result":null,"error":{...}}`, so `outcome()`
// reads the error first.

import Foundation

public struct Request: Codable, Equatable, Sendable {
	public var id: Int
	public var cmd: String
	public var params: [String: JSONValue] = [:]

	public init(id: Int, cmd: String, params: [String: JSONValue] = [:]) {
		self.id = id
		self.cmd = cmd
		self.params = params
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		id = try box.decode(Int.self, forKey: .id)
		cmd = try box.decode(String.self, forKey: .cmd)
		params = try box.decode([String: JSONValue].self, forKey: .params, orDefault: params)
	}

	public func params<Value: Decodable>(as type: Value.Type) throws -> Value {
		try JSONValue.object(params).decoded(as: type)
	}
}

public struct ErrorInfo: Codable, Equatable, Sendable {
	public var message: String

	public init(message: String) {
		self.message = message
	}
}

public struct Response: Codable, Equatable, Sendable {
	public enum Outcome: Equatable, Sendable {
		case success(JSONValue)
		case failure(ErrorInfo)
	}

	public var id: Int
	public var result: JSONValue?
	public var error: ErrorInfo?

	public init(id: Int, result: JSONValue? = nil, error: ErrorInfo? = nil) {
		self.id = id
		self.result = result
		self.error = error
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		id = try box.decode(Int.self, forKey: .id)
		// A result sent as null is an answer; a frame with no result key carries none.
		result = box.contains(.result) ? try box.decode(JSONValue.self, forKey: .result) : nil
		error = try box.decodeIfPresent(ErrorInfo.self, forKey: .error)
	}

	public static func succeeded(id: Int, with value: some Encodable) throws -> Response {
		Response(id: id, result: try JSONValue(encoding: value))
	}

	public static func failed(id: Int, message: String) -> Response {
		Response(id: id, error: ErrorInfo(message: message))
	}

	public func outcome() throws -> Outcome {
		if let error {
			return .failure(error)
		}
		guard let result else {
			throw ValidationError(path: "Response.result", reason: "frame carries neither a result nor an error")
		}
		return .success(result)
	}
}
