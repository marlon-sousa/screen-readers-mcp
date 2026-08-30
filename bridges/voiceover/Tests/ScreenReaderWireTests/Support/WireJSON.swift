// Test scaffolding -- NOT a port double, which is why it is in Support/ rather
// than in a Fakes/ directory (the repo's rule: fakes/ holds exactly the port
// doubles and nothing else). The wire binding has no ports to fake.
//
// Every test here starts from a JSON LINE, spelled out as a peer would send it,
// rather than from a Swift value: what these types are for is meeting another
// implementation, and a test that only ever round-trips Swift values would pass
// happily with a field name nobody else uses.

import Foundation

@testable import ScreenReaderWire

enum WireJSON {
	/// Decode a shape from the JSON text a peer would put on the wire.
	static func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
		try JSONDecoder().decode(type, from: Data(json.utf8))
	}

	/// Decode the way a HANDLER does -- through JSONValue, which is the
	/// conversion that raises a ValidationError naming the field rather than a
	/// DecodingError describing a coding path.
	static func decodeThroughValue<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
		try value(json).decoded(as: type)
	}

	/// Parse JSON text into the open value the envelope carries.
	static func value(_ json: String) throws -> JSONValue {
		try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
	}

	/// Encode a shape and read it back as an open value, so a test can assert on
	/// exactly what was emitted -- including which keys were not.
	static func encoded(_ value: some Encodable) throws -> JSONValue {
		let data = try JSONEncoder().encode(value)
		return try JSONDecoder().decode(JSONValue.self, from: data)
	}

	/// Encode a shape and decode it back -- the round trip a peer performs when
	/// it answers, which is the only thing that proves the two halves of a
	/// hand-written Codable agree with each other.
	static func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
		try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
	}

	/// The keys of an encoded shape, sorted, for asserting what travels.
	static func keys(of value: some Encodable) throws -> [String] {
		guard case .object(let fields) = try encoded(value) else { return [] }
		return fields.keys.sorted()
	}
}
