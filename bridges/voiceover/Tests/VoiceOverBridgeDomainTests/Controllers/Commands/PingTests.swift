// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/Ping.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("PingHandler")
struct PingTests {
	private func context(adapters: AdapterSet? = nil) -> SessionContext {
		let context = SessionContext(
			clock: FakeClock(), transcript: FakeTranscript(), attended: true, close: { _ in })
		context.adapters = adapters
		return context
	}

	@Test("BEFORE THE HANDSHAKE it says nothing about suppression, because it cannot know")
	func itAnswersOk() throws {
		let result = try PingHandler().execute(
			context(), Request(id: 1, cmd: Command.ping.rawValue)
		) as? PingResult
		let ping = try #require(result)
		#expect(ping.ok)
		// nil is a THIRD answer, not a false one: with no silence control there is
		// nothing to ask, and reporting `false` would be read as proof that the
		// human can hear their machine.
		#expect(ping.suppressing == nil)
	}

	@Test("in a SILENT session it reports that words are being withheld right now")
	func itReportsSuppression() throws {
		// The one channel an agent has for noticing a lift: nothing is pushed when
		// the silence cap fires (protocol.md §6.1, rule 3), so an agent that wants
		// to know reads this.
		let silence = FakeSilenceControl()
		try silence.suppress()
		let result = try PingHandler().execute(
			context(adapters: fakeAdapterSet(mode: .silent, silenceControl: silence)),
			Request(id: 1, cmd: Command.ping.rawValue)) as? PingResult
		#expect(try #require(result).suppressing == true)
	}

	@Test("after a lift it reports FALSE, which is how an agent learns the room got loud")
	func itReportsALift() throws {
		let silence = FakeSilenceControl()
		try silence.suppress()
		try silence.passThrough()
		let result = try PingHandler().execute(
			context(adapters: fakeAdapterSet(mode: .silent, silenceControl: silence)),
			Request(id: 1, cmd: Command.ping.rawValue)) as? PingResult
		#expect(try #require(result).suppressing == false)
	}

	@Test("it is the one handler that does not reset the inactivity watchdog")
	func itDoesNotResetInactivity() {
		#expect(!PingHandler().resetsInactivity)
		#expect(!PingHandler().availableBeforeHello)
	}
}
