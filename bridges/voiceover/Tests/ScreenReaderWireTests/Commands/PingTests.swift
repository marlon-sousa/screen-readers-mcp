// Mirrors Sources/ScreenReaderWire/Commands/Ping.swift.

import Testing

@testable import ScreenReaderWire

@Suite("ping")
struct PingTests {
	@Test("an empty result means alive, and says nothing about suppression")
	func emptyResult() throws {
		let result = try WireJSON.decode(PingResult.self, "{}")
		#expect(result.ok)
		#expect(result.suppressing == nil)
	}

	@Test("suppression is three-valued: yes, no, and cannot tell")
	func suppressingIsThreeValued() throws {
		#expect(try WireJSON.decode(PingResult.self, #"{"suppressing":true}"#).suppressing == true)
		#expect(try WireJSON.decode(PingResult.self, #"{"suppressing":false}"#).suppressing == false)
		#expect(try WireJSON.decode(PingResult.self, #"{"ok":true}"#).suppressing == nil)
	}
}
