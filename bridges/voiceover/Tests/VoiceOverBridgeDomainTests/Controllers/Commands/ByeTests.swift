// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/Bye.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("ByeHandler")
struct ByeTests {
	@Test("it asks the session to end, with the reason that says the client meant to")
	func itClosesWithClientBye() throws {
		var reasons: [TeardownReason] = []
		let context = SessionContext(
			clock: FakeClock(),
			transcript: FakeTranscript(),
			attended: true,
			close: { reasons.append($0) }
		)
		let result = try ByeHandler().execute(context, Request(id: 9, cmd: Command.bye.rawValue))
		#expect(reasons == [.clientBye])
		#expect((result as? AckResult)?.ok == true)
	}
}
