// Mirrors Sources/ScreenReaderWire/Commands/GetSpeech.swift.

import Testing

@testable import ScreenReaderWire

@Suite("getSpeech")
struct GetSpeechTests {
	@Test("the range is half-open, so the next call resumes at toIndex")
	func rangeIsHalfOpen() throws {
		let json = """
		{"entries":[{"text":"one","index":2,"logPosition":0},{"text":"two","index":3,"logPosition":0}],\
		"fromIndex":2,"toIndex":4}
		"""
		let result = try WireJSON.decode(SpeechResult.self, json)
		#expect(result.entries.map(\.index) == [2, 3])
		#expect(result.toIndex == 4)
		#expect(GetSpeechParams(sinceIndex: result.toIndex).sinceIndex == 4)
	}

	@Test("an empty slice still says where it looked")
	func emptySliceCarriesItsRange() throws {
		let result = try WireJSON.decode(SpeechResult.self, #"{"entries":[],"fromIndex":9,"toIndex":9}"#)
		#expect(result.entries.isEmpty)
		#expect(result.fromIndex == 9)
	}

	@Test("sinceIndex is required -- a slice with no start is not a question")
	func sinceIndexIsRequired() {
		#expect(throws: (any Error).self) {
			try WireJSON.decode(GetSpeechParams.self, "{}")
		}
	}
}
