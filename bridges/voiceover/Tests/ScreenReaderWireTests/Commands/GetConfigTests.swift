// Mirrors Sources/ScreenReaderWire/Commands/GetConfig.swift.

import Testing

@testable import ScreenReaderWire

@Suite("getConfig")
struct GetConfigTests {
	@Test("a key path is a path into the reader's own tree")
	func keyPath() throws {
		let params = try WireJSON.decode(GetConfigParams.self, #"{"keyPath":["speech","rate"]}"#)
		#expect(params.keyPath == ["speech", "rate"])
	}

	@Test("the value is whatever the reader holds, of whatever shape")
	func valueIsOpen() throws {
		#expect(try WireJSON.decode(ConfigResult.self, #"{"value":50}"#).value == .int(50))
		#expect(try WireJSON.decode(ConfigResult.self, #"{"value":{"a":[true]}}"#).value
			== .object(["a": .array([.bool(true)])]))
	}

	@Test("a null setting is a value, so the key must still be there")
	func nullIsAValue() throws {
		#expect(try WireJSON.decode(ConfigResult.self, #"{"value":null}"#).value == .null)
		#expect(throws: (any Error).self) {
			try WireJSON.decode(ConfigResult.self, "{}")
		}
	}
}
