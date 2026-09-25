// Mirrors Sources/ScreenReaderWire/Commands/AskUser.swift.

import Testing

@testable import ScreenReaderWire

@Suite("askUser")
struct AskUserTests {
	@Test("asking answers with a ticket rather than with a reply")
	func ticketNotReply() throws {
		let result = try WireJSON.decode(AskUserResult.self, #"{"ticket":"q-1"}"#)
		#expect(result.ticket == "q-1")
	}

	@Test("a prompt is required, and a ticket is")
	func bothRequired() {
		#expect(throws: (any Error).self) {
			try WireJSON.decode(AskUserParams.self, "{}")
		}
		#expect(throws: (any Error).self) {
			try WireJSON.decode(AskUserResult.self, "{}")
		}
	}
}
