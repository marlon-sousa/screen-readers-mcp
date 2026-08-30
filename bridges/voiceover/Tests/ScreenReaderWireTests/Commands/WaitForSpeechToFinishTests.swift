// Mirrors Sources/ScreenReaderWire/Commands/WaitForSpeechToFinish.swift.

import Testing

@testable import ScreenReaderWire

@Suite("waitForSpeechToFinish")
struct WaitForSpeechToFinishTests {
	@Test("an empty params object means the contract's five-second wait")
	func timeoutDefaults() throws {
		#expect(try WireJSON.decode(WaitToFinishParams.self, "{}").timeout == 5.0)
	}

	@Test("a caller may ask for longer, and a fraction is a number like any other")
	func timeoutIsANumber() throws {
		#expect(try WireJSON.decode(WaitToFinishParams.self, #"{"timeout":0.25}"#).timeout == 0.25)
	}

	@Test("not finishing in time is reported, not raised")
	func unfinishedIsAnAnswer() throws {
		#expect(try !WireJSON.decode(WaitToFinishResult.self, #"{"finished":false}"#).finished)
	}
}
