// Mirrors Sources/ScreenReaderWire/Commands/TypeText.swift.

import Testing

@testable import ScreenReaderWire

@Suite("typeText")
struct TypeTextTests {
	@Test("typing's grace window defaults to 0, unlike a gesture's 100")
	func graceDefaultsToZero() throws {
		// Not an oversight in either direction: typing produces its speech as the
		// keys land, a gesture produces it afterwards.
		let params = try WireJSON.decode(TypeParams.self, #"{"text":"hello"}"#)
		#expect(params.graceMs == 0)
		#expect(PressGestureParams(gestures: []).graceMs == 100)
	}

	@Test("the result counts characters and never carries them back")
	func resultCountsOnly() throws {
		let json = #"{"typed":5,"speech":[],"speechFrom":0,"speechTo":0}"#
		let result = try WireJSON.decode(TypeResult.self, json)
		#expect(result.typed == 5)
		#expect(try WireJSON.keys(of: result) == ["speech", "speechFrom", "speechTo", "typed"])
	}

	@Test("text is required -- typing nothing is a fault, not a no-op")
	func textIsRequired() {
		#expect(throws: (any Error).self) {
			try WireJSON.decode(TypeParams.self, #"{"graceMs":10}"#)
		}
	}
}
