// Mirrors Sources/ScreenReaderWire/Commands/SetLogLevel.swift.

import Testing

@testable import ScreenReaderWire

@Suite("setLogLevel")
struct SetLogLevelTests {
	@Test("the answer names the previous level as well as the new one")
	func previousIsReported() throws {
		let result = try WireJSON.decode(LogLevelResult.self, #"{"level":"debug","previous":"info"}"#)
		#expect(result.level == .debug)
		#expect(result.previous == .info)
	}

	@Test("both levels are required, and both are from the closed set")
	func bothRequiredAndClosed() {
		#expect(throws: (any Error).self) {
			try WireJSON.decode(LogLevelResult.self, #"{"level":"debug"}"#)
		}
		#expect(throws: (any Error).self) {
			try WireJSON.decode(SetLogLevelParams.self, #"{"level":"chatty"}"#)
		}
	}
}
