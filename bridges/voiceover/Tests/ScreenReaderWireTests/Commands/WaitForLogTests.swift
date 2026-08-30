// Mirrors Sources/ScreenReaderWire/Commands/WaitForLog.swift.

import Testing

@testable import ScreenReaderWire

@Suite("waitForLog")
struct WaitForLogTests {
	@Test("the wait defaults to five seconds with no filter at all")
	func defaults() throws {
		let params = try WireJSON.decode(WaitForLogParams.self, "{}")
		#expect(params.timeout == 5.0)
		#expect(params.minLevel == nil)
		#expect(params.contains == nil)
	}

	@Test("a timeout still reports where reading got to")
	func timeoutCarriesAPosition() throws {
		let result = try WireJSON.decode(WaitForLogResult.self, #"{"found":false,"position":4096}"#)
		#expect(!result.found)
		#expect(result.position == 4096)
		#expect(result.text.isEmpty)
	}
}
