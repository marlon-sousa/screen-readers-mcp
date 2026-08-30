// Mirrors Sources/ScreenReaderWire/Commands/Announce.swift.

import Testing

@testable import ScreenReaderWire

@Suite("announce")
struct AnnounceTests {
	@Test("an announcement is a text, and it is required")
	func textIsRequired() throws {
		#expect(try WireJSON.decode(AnnounceParams.self, #"{"text":"starting"}"#).text == "starting")
		#expect(throws: (any Error).self) {
			try WireJSON.decode(AnnounceParams.self, "{}")
		}
	}

	@Test("an empty announcement is allowed, and says nothing")
	func emptyTextIsAllowed() throws {
		#expect(try WireJSON.decode(AnnounceParams.self, #"{"text":""}"#).text.isEmpty)
	}
}
