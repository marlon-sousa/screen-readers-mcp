// Mirrors Sources/ScreenReaderWire/Commands/WaitForSpeech.swift.

import Testing

@testable import ScreenReaderWire

@Suite("waitForSpeech")
struct WaitForSpeechTests {
	@Test("the timeout defaults to five seconds and the anchor to nothing")
	func defaults() throws {
		let params = try WireJSON.decode(WaitForSpeechParams.self, #"{"text":"saved"}"#)
		#expect(params.timeout == 5.0)
		#expect(params.afterIndex == nil)
	}

	@Test("afterIndex 0 anchors at the start, and is not read as unset")
	func zeroAnchorIsMeant() throws {
		let params = try WireJSON.decode(WaitForSpeechParams.self, #"{"text":"saved","afterIndex":0}"#)
		#expect(params.afterIndex == 0)
	}

	@Test("a timeout is a normal answer: found is false and the shape is complete")
	func timeoutIsAnAnswer() throws {
		let result = try WireJSON.decode(WaitForSpeechResult.self, #"{"found":false,"index":11,"text":""}"#)
		#expect(!result.found)
		#expect(result.index == 11)
		#expect(result.emittedAt.isEmpty)
	}

	@Test("a hit carries the entry's own coordinates")
	func hitCarriesCoordinates() throws {
		let json = #"{"found":true,"index":11,"text":"saved","logPosition":404,"emittedAt":"2026-08-30T09:00:00Z"}"#
		let result = try WireJSON.decode(WaitForSpeechResult.self, json)
		#expect(result.logPosition == 404)
		#expect(result.emittedAt == "2026-08-30T09:00:00Z")
	}
}
