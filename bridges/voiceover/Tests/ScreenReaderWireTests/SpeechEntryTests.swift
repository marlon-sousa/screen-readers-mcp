// Mirrors Sources/ScreenReaderWire/SpeechEntry.swift.

import Testing

@testable import ScreenReaderWire

@Suite("SpeechEntry")
struct SpeechEntryTests {
	@Test("an entry from a reader with no clock decodes with an empty timestamp")
	func emittedAtDefaults() throws {
		let entry = try WireJSON.decode(SpeechEntry.self, #"{"text":"one","index":3,"logPosition":0}"#)
		#expect(entry.emittedAt.isEmpty)
	}

	@Test("the three coordinates are required, and a missing one is named")
	func requiredFields() {
		#expect(throws: (any Error).self) {
			try WireJSON.decode(SpeechEntry.self, #"{"text":"one","index":3}"#)
		}
	}

	@Test("an entry round-trips through the wire unchanged")
	func roundTrip() throws {
		let entry = SpeechEntry(text: "two", index: 4, logPosition: 91, emittedAt: "2026-08-30T10:00:00+01:00")
		#expect(try WireJSON.roundTrip(entry) == entry)
	}
}
