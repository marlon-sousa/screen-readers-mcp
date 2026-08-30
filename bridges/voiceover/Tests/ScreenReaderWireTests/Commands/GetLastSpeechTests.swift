// Mirrors Sources/ScreenReaderWire/Commands/GetLastSpeech.swift.

import Testing

@testable import ScreenReaderWire

@Suite("getLastSpeech")
struct GetLastSpeechTests {
	@Test("a reader with no log and no clock answers with text and an index alone")
	func minimalAnswer() throws {
		let result = try WireJSON.decode(LastSpeechResult.self, #"{"text":"button","index":7}"#)
		#expect(result.logPosition == 0)
		#expect(result.emittedAt.isEmpty)
	}

	@Test("nothing said yet is an empty text, not an error")
	func emptyBufferIsAnAnswer() throws {
		#expect(try WireJSON.decode(LastSpeechResult.self, #"{"text":"","index":0}"#).text.isEmpty)
	}
}
