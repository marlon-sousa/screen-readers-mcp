// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/WaitForSpeechToFinish.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("WaitForSpeechToFinishHandler")
struct WaitForSpeechToFinishTests {
	private let clock = FakeClock()

	private func context() -> SessionContext {
		let context = SessionContext(
			clock: clock, transcript: FakeTranscript(), attended: true, close: { _ in }
		)
		context.speech = SpeechBuffer(clock: clock)
		return context
	}

	private func finished(_ context: SessionContext, timeout: Double) throws -> Bool {
		let value = try WaitForSpeechToFinishHandler().execute(
			context,
			Request(
				id: 1, cmd: Command.waitForSpeechToFinish.rawValue, params: ["timeout": .double(timeout)]
			)
		)
		return try #require(value as? WaitToFinishResult).finished
	}

	@Test("it settles once the feed has been quiet for the settle window")
	func itSettles() throws {
		let ctx = context()
		ctx.speech?.append(CapturedUtterance(text: "said"))
		#expect(try finished(ctx, timeout: 5))
		// In advances, not seconds: the wait is measured on the injected clock.
		#expect(clock.sleeps.reduce(0, +) > 0)
	}

	@Test("an utterance that just arrived is not finished, and a zero timeout says so")
	func stillSpeaking() throws {
		let ctx = context()
		ctx.speech?.append(CapturedUtterance(text: "said"))
		#expect(try finished(ctx, timeout: 0) == false)
	}

	@Test("the timeout has a default, so a caller that sends none still gets an answer")
	func theTimeoutDefaults() throws {
		let ctx = context()
		let value = try WaitForSpeechToFinishHandler().execute(
			ctx, Request(id: 1, cmd: Command.waitForSpeechToFinish.rawValue, params: [:])
		)
		#expect(try #require(value as? WaitToFinishResult).finished)
	}
}
