// ROLE: entity -- any JSON value, as a value type. The Swift counterpart of the
// contract's open shapes: `Request.params`, `Response.result`, `EchoParams
// .payload`, `ConfigResult.value` and `NormalizedSetting`'s two settings, all of
// which the schema writes as the empty schema `{}` and Python writes as `Any`.
//
// Pure. Used by Envelope (which carries a command's payload before anybody knows
// which command it is) and by every shape with an open field.
//
// AMENDMENT TO SPEC 0046's 13.3 LAYOUT, with its why: the spec's file table has
// no entry for this, because Python needs none -- `Any` is a type there. Swift
// has no such type that is also Codable, so the contract's open fields need a
// value that can hold one, and the two conversions below are what let a handler
// move between the envelope's open payload and its own typed params.

import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
	case null
	case bool(Bool)
	case int(Int)
	case double(Double)
	case string(String)
	case array([JSONValue])
	case object([String: JSONValue])

	public init(from decoder: any Decoder) throws {
		let box = try decoder.singleValueContainer()
		// Bool before Int because a JSON `true` is not a number, and Int before
		// Double so that an integer survives a round trip as an integer.
		if box.decodeNil() {
			self = .null
		} else if let value = try? box.decode(Bool.self) {
			self = .bool(value)
		} else if let value = try? box.decode(Int.self) {
			self = .int(value)
		} else if let value = try? box.decode(Double.self) {
			self = .double(value)
		} else if let value = try? box.decode(String.self) {
			self = .string(value)
		} else if let value = try? box.decode([JSONValue].self) {
			self = .array(value)
		} else if let value = try? box.decode([String: JSONValue].self) {
			self = .object(value)
		} else {
			throw DecodingError.dataCorruptedError(in: box, debugDescription: "not a JSON value")
		}
	}

	public func encode(to encoder: any Encoder) throws {
		var box = encoder.singleValueContainer()
		switch self {
		case .null: try box.encodeNil()
		case .bool(let value): try box.encode(value)
		case .int(let value): try box.encode(value)
		case .double(let value): try box.encode(value)
		case .string(let value): try box.encode(value)
		case .array(let value): try box.encode(value)
		case .object(let value): try box.encode(value)
		}
	}

	/// Hold `value`'s JSON rendering -- how a handler puts its typed result into
	/// a `Response`.
	public init<Value: Encodable>(encoding value: Value) throws {
		let data = try JSONEncoder().encode(value)
		self = try JSONDecoder().decode(JSONValue.self, from: data)
	}

	/// Read this value as `type` -- how a handler reads its typed params out of
	/// a `Request`. Raises a ValidationError naming the field that did not fit.
	public func decoded<Value: Decodable>(as type: Value.Type) throws -> Value {
		let data = try JSONEncoder().encode(self)
		do {
			return try JSONDecoder().decode(type, from: data)
		} catch {
			throw ValidationError(decoding: type, error: error)
		}
	}
}
