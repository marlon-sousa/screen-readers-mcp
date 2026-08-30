// ROLE: entity -- the two frames every session exchanges, and the error one of
// them may carry.
//
// Pure. Decoded and encoded by JsonLinesChannel (entry 13.4's adapter): FRAMING
// IS NOT HERE, for the same reason it is an adapter in the NVDA bridge. This
// file knows what a frame IS; the adapter knows that frames are separated by
// newlines and arrive in pieces.
//
// `cmd` IS A RAW STRING, NOT A Command. An unrecognised command must reach the
// registry as data so it can be answered "unknown command", and a typed field
// would instead fail to decode the whole frame -- turning a clean error into a
// protocol fault. Command.swift's header carries the same note from its side.
//
// AN ERROR FRAME FROM THE PYTHON BRIDGE CARRIES BOTH KEYS, and this is measured
// rather than assumed: its `to_dict` renders every dataclass field, so a failure
// arrives as `{"id":7,"result":null,"error":{...}}`. "Exactly one of" is
// therefore a rule about MEANING, not about which keys are present -- which is
// why `outcome()` reads the error first and why it is a function that can fail
// rather than a stored property that pretends the frame is always well formed.

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

	/// Read the params as the command's own shape -- the seam between the
	/// envelope, which is the same for every command, and the per-command types
	/// this module defines. Raises a ValidationError naming the offending field.
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
	/// What a well-formed reply frame says, once. See the header for why reading
	/// it is a function rather than a stored property.
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
		// `contains` rather than decodeIfPresent, because for THIS field the two
		// absences differ: a result sent as null is an answer, and a frame with no
		// result key at all carries none. Decoding.swift's header is the general
		// form of the same rule.
		result = box.contains(.result) ? try box.decode(JSONValue.self, forKey: .result) : nil
		error = try box.decodeIfPresent(ErrorInfo.self, forKey: .error)
	}

	/// A reply carrying `value`, which is a command's own result shape.
	public static func succeeded(id: Int, with value: some Encodable) throws -> Response {
		Response(id: id, result: try JSONValue(encoding: value))
	}

	/// A reply carrying a failure. `result` stays nil here; a peer that sends an
	/// explicit null beside its error is honoured by `outcome()`, not imitated.
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
