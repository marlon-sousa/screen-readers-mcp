// Mirrors Sources/ScreenReaderWire/Commands/GetNextSpeechIndex.swift.

import Testing

@testable import ScreenReaderWire

@Suite("getNextSpeechIndex")
struct GetNextSpeechIndexTests {
	@Test("the answer is a bare index a session marks its place with")
	func index() throws {
		#expect(try WireJSON.decode(NextIndexResult.self, #"{"index":12}"#).index == 12)
	}

	@Test("a fresh session's mark is zero, which is a mark like any other")
	func zeroIsAMark() throws {
		#expect(try WireJSON.decode(NextIndexResult.self, #"{"index":0}"#).index == 0)
	}
}
