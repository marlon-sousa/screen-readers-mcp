// Mirrors Sources/ScreenReaderWire/Commands/SetConfig.swift.

import Testing

@testable import ScreenReaderWire

@Suite("setConfig")
struct SetConfigTests {
	@Test("a write names its path and carries whatever value the reader takes")
	func writeShape() throws {
		let params = try WireJSON.decode(SetConfigParams.self, #"{"keyPath":["speech","rate"],"value":"fast"}"#)
		#expect(params.keyPath == ["speech", "rate"])
		#expect(params.value == .string("fast"))
	}

	@Test("both halves are required -- a write with no value is not a write")
	func bothRequired() {
		#expect(throws: (any Error).self) {
			try WireJSON.decode(SetConfigParams.self, #"{"keyPath":["speech"]}"#)
		}
	}
}
