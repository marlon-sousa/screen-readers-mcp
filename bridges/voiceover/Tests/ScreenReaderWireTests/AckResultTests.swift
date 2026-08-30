// Mirrors Sources/ScreenReaderWire/AckResult.swift.

import Testing

@testable import ScreenReaderWire

@Suite("AckResult")
struct AckResultTests {
	@Test("an empty object means it worked")
	func emptyObjectIsOk() throws {
		#expect(try WireJSON.decode(AckResult.self, "{}").ok)
	}

	@Test("a peer that says otherwise is believed")
	func falseIsCarried() throws {
		#expect(try !WireJSON.decode(AckResult.self, #"{"ok":false}"#).ok)
	}
}
