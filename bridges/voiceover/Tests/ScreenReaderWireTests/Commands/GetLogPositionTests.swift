// Mirrors Sources/ScreenReaderWire/Commands/GetLogPosition.swift.

import Testing

@testable import ScreenReaderWire

@Suite("getLogPosition")
struct GetLogPositionTests {
	@Test("a position is a coordinate and a readable instant, both required")
	func shape() throws {
		let result = try WireJSON.decode(LogPositionResult.self, #"{"position":4096,"time":"2026-08-30T09:00:00Z"}"#)
		#expect(result.position == 4096)
		#expect(result.time == "2026-08-30T09:00:00Z")
		#expect(throws: (any Error).self) {
			try WireJSON.decode(LogPositionResult.self, #"{"position":4096}"#)
		}
	}
}
