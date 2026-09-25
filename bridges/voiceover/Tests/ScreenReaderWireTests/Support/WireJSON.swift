// Test scaffolding: decode and encode helpers that start from JSON text as a peer would send it.

import Foundation

@testable import ScreenReaderWire

enum WireJSON {
	static func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
		try JSONDecoder().decode(type, from: Data(json.utf8))
	}

	/// Decodes through JSONValue, as a handler does, so a failure is a ValidationError naming the field.
	static func decodeThroughValue<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
		try value(json).decoded(as: type)
	}

	static func value(_ json: String) throws -> JSONValue {
		try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
	}

	static func encoded(_ value: some Encodable) throws -> JSONValue {
		let data = try JSONEncoder().encode(value)
		return try JSONDecoder().decode(JSONValue.self, from: data)
	}

	static func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
		try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
	}

	static func keys(of value: some Encodable) throws -> [String] {
		guard case .object(let fields) = try encoded(value) else { return [] }
		return fields.keys.sorted()
	}
}
