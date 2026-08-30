// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/GetLastSpeech.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("GetLastSpeechHandler")
struct GetLastSpeechTests {
	private let clock = FakeClock()

	private func context() -> SessionContext {
		let context = SessionContext(
			clock: clock, transcript: FakeTranscript(), attended: true, close: { _ in }
		)
		context.speech = SpeechBuffer(clock: clock)
		return context
	}

	private func result(_ context: SessionContext) throws -> LastSpeechResult {
		let value = try GetLastSpeechHandler().execute(
			context, Request(id: 1, cmd: Command.getLastSpeech.rawValue, params: [:])
		)
		return try #require(value as? LastSpeechResult)
	}

	@Test("it answers with the most recent utterance and the index it sits at")
	func theMostRecent() throws {
		let ctx = context()
		ctx.speech?.append(CapturedUtterance(text: "first", emittedAt: 1_700_000_000))
		ctx.speech?.append(CapturedUtterance(text: "second", emittedAt: 1_700_000_002))
		let result = try result(ctx)
		#expect(result.text == "second")
		#expect(result.index == 2)
		#expect(result.emittedAt == Wallclock.format(1_700_000_002))
	}

	@Test("an untouched session answers with an empty text and an EMPTY stamp, not an error")
	func theSentinelAnswers() throws {
		let result = try result(context())
		#expect(result.text.isEmpty)
		#expect(result.index == 0)
		// Nothing was emitted, so there is no instant to report -- and reporting
		// one would claim something happened (spec 0028).
		#expect(result.emittedAt.isEmpty)
	}

	@Test("logPosition is 0, because VoiceOver has no journal to position into")
	func noJournalCoordinate() throws {
		let ctx = context()
		ctx.speech?.append(CapturedUtterance(text: "said"))
		#expect(try result(ctx).logPosition == 0)
	}

	@Test("read before hello, it fails with a readable error rather than a crash")
	func withoutABuffer() {
		let ctx = SessionContext(
			clock: clock, transcript: FakeTranscript(), attended: true, close: { _ in }
		)
		#expect(throws: CommandError.self) {
			try GetLastSpeechHandler().execute(ctx, Request(id: 1, cmd: "getLastSpeech", params: [:]))
		}
	}
}
