// ROLE: entity, any JSON value, for the contract's open shapes.

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
		// Bool before Int because a JSON `true` is not a number, and Int before Double so an integer stays one.
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

	public init<Value: Encodable>(encoding value: Value) throws {
		let data = try JSONEncoder().encode(value)
		self = try JSONDecoder().decode(JSONValue.self, from: data)
	}

	/// Throws a ValidationError naming the field that did not fit.
	public func decoded<Value: Decodable>(as type: Value.Type) throws -> Value {
		let data = try JSONEncoder().encode(self)
		do {
			return try JSONDecoder().decode(type, from: data)
		} catch {
			throw ValidationError(decoding: type, error: error)
		}
	}
}
