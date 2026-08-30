// Mirrors Sources/ScreenReaderWire/LogLevel.swift.

import Testing

@testable import ScreenReaderWire

@Suite("LogLevel")
struct LogLevelTests {
	@Test("the six levels are the contract's, spelled as it spells them")
	func vocabulary() {
		#expect(LogLevel.allCases.map(\.rawValue) == ["debug", "io", "debugwarning", "info", "warning", "error"])
	}

	@Test("`debugwarning` is one word, which is the spelling a peer sends")
	func debugWarningIsOneWord() throws {
		#expect(try WireJSON.decode(LogLevel.self, #""debugwarning""#) == .debugwarning)
	}

	@Test("a level outside the set is refused")
	func unknownLevelIsRefused() {
		#expect(throws: (any Error).self) {
			try WireJSON.decode(LogLevel.self, #""trace""#)
		}
	}
}
