// Mirrors Sources/ScreenReaderWire/Commands/WaitForUserReply.swift.

import Testing

@testable import ScreenReaderWire

@Suite("waitForUserReply")
struct WaitForUserReplyTests {
	@Test("the wait for a human defaults to thirty seconds, not five")
	func timeoutDefaults() throws {
		// The thing being waited for is a person reading and deciding.
		let params = try WireJSON.decode(WaitForUserReplyParams.self, #"{"ticket":"q-1"}"#)
		#expect(params.timeout == 30.0)
		#expect(WaitToFinishParams().timeout == 5.0)
	}

	@Test("no reply in time is an answer with an empty text")
	func unansweredIsAnAnswer() throws {
		let result = try WireJSON.decode(WaitForUserReplyResult.self, #"{"answered":false}"#)
		#expect(!result.answered)
		#expect(result.text.isEmpty)
	}

	@Test("a reply carries the human's words")
	func answered() throws {
		let result = try WireJSON.decode(WaitForUserReplyResult.self, #"{"answered":true,"text":"go ahead"}"#)
		#expect(result.text == "go ahead")
	}
}
