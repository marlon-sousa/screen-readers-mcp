// Mirrors Sources/ScreenReaderWire/JSONValue.swift.
//
// This type is what the contract's open fields hold, so its tests are about
// FIDELITY: whatever a peer sent has to survive being held and handed back.

import Testing

@testable import ScreenReaderWire

@Suite("JSONValue")
struct JSONValueTests {
	@Test("every JSON kind decodes as itself")
	func kinds() throws {
		#expect(try WireJSON.value("null") == .null)
		#expect(try WireJSON.value("true") == .bool(true))
		#expect(try WireJSON.value("7") == .int(7))
		#expect(try WireJSON.value("7.5") == .double(7.5))
		#expect(try WireJSON.value(#""seven""#) == .string("seven"))
		#expect(try WireJSON.value("[1,2]") == .array([.int(1), .int(2)]))
		#expect(try WireJSON.value(#"{"a":1}"#) == .object(["a": .int(1)]))
	}

	@Test("a boolean is not read as a number, and an integer is not read as a double")
	func scalarsAreNotConfused() throws {
		// Order matters in the decoder: `true` would decode as 1 in a language
		// that tried Int first, and an integer that came back as 7.0 would change
		// what a round trip means for an index.
		#expect(try WireJSON.value("true") != .int(1))
		#expect(try WireJSON.value("7") != .double(7))
	}

	@Test("a nested value round-trips unchanged")
	func roundTrip() throws {
		let json = #"{"a":[1,{"b":null},"c"],"d":{"e":true}}"#
		let value = try WireJSON.value(json)
		#expect(try WireJSON.encoded(value) == value)
	}

	@Test("a typed result becomes an open value a Response can carry")
	func encodingATypedShape() throws {
		let value = try JSONValue(encoding: AckResult(ok: true))
		#expect(value == .object(["ok": .bool(true)]))
	}

	@Test("and comes back out as the type a handler asked for")
	func decodingBackToATypedShape() throws {
		let value = JSONValue.object(["ok": .bool(false)])
		#expect(try value.decoded(as: AckResult.self) == AckResult(ok: false))
	}

	@Test("a value that does not fit the type raises a ValidationError naming the field")
	func mismatchNamesTheField() {
		let value = JSONValue.object(["ok": .string("yes")])
		#expect(throws: ValidationError.self) {
			try value.decoded(as: AckResult.self)
		}
	}
}
