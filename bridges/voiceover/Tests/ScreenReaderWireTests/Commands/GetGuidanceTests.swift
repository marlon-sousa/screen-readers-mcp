// Mirrors Sources/ScreenReaderWire/Commands/GetGuidance.swift.

import Testing

@testable import ScreenReaderWire

@Suite("getGuidance")
struct GetGuidanceTests {
	@Test("an unrecognised persona still gets guidance, and is told it was not recognised")
	func recognisedIsReported() throws {
		let json = #"{"persona":"archaeologist","recognised":false,"text":"the general text"}"#
		let result = try WireJSON.decode(GetGuidanceResult.self, json)
		#expect(!result.recognised)
		#expect(!result.text.isEmpty)
	}

	@Test("all three fields are required -- guidance with no text is not guidance")
	func allRequired() {
		#expect(throws: (any Error).self) {
			try WireJSON.decode(GetGuidanceResult.self, #"{"persona":"tester","recognised":true}"#)
		}
	}
}
