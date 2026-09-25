// Mirrors Sources/ScreenReaderWire/Commands/GetBraille.swift.

import Testing

@testable import ScreenReaderWire

@Suite("getBraille")
struct GetBrailleTests {
	@Test("a braille entry is indexed and half-open exactly as speech is")
	func entriesMirrorSpeech() throws {
		let json = """
		{"entries":[{"text":"btn OK","index":0,"logPosition":12}],"fromIndex":0,"toIndex":1}
		"""
		let result = try WireJSON.decode(BrailleResult.self, json)
		#expect(result.entries[0].text == "btn OK")
		#expect(result.entries[0].emittedAt.isEmpty)
		#expect(result.toIndex == 1)
	}

	@Test("the entry's three coordinates are required")
	func coordinatesRequired() {
		#expect(throws: (any Error).self) {
			try WireJSON.decode(BrailleEntry.self, #"{"text":"btn OK","index":0}"#)
		}
	}
}
