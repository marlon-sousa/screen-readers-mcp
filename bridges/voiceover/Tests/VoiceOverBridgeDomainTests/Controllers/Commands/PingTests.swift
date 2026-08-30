// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/Ping.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("PingHandler")
struct PingTests {
	private func context() -> SessionContext {
		SessionContext(clock: FakeClock(), transcript: FakeTranscript(), attended: true, close: { _ in })
	}

	@Test("it answers ok, and says nothing it cannot know about suppression")
	func itAnswersOk() throws {
		let result = try PingHandler().execute(
			context(), Request(id: 1, cmd: Command.ping.rawValue)
		) as? PingResult
		let ping = try #require(result)
		#expect(ping.ok)
		// nil is a THIRD answer, not a false one: nothing in this build can
		// suppress speech, so reporting `false` would be read as proof that the
		// human can hear their machine. 13.6 is where it becomes an answer.
		#expect(ping.suppressing == nil)
	}

	@Test("it is the one handler that does not reset the inactivity watchdog")
	func itDoesNotResetInactivity() {
		#expect(!PingHandler().resetsInactivity)
		#expect(!PingHandler().availableBeforeHello)
	}
}
