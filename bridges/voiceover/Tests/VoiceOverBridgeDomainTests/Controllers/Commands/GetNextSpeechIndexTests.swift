// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/GetNextSpeechIndex.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("GetNextSpeechIndexHandler")
struct GetNextSpeechIndexTests {
	private let clock = FakeClock()

	private func context() -> SessionContext {
		let context = SessionContext(
			clock: clock, transcript: FakeTranscript(), attended: true, close: { _ in }
		)
		context.speech = SpeechBuffer(clock: clock)
		return context
	}

	private func index(_ context: SessionContext) throws -> Int {
		let value = try GetNextSpeechIndexHandler().execute(
			context, Request(id: 1, cmd: Command.getNextSpeechIndex.rawValue, params: [:])
		)
		return try #require(value as? NextIndexResult).index
	}

	@Test("it is the index the NEXT utterance will get, so a mark taken now excludes what came before")
	func theBookmarkIsAhead() throws {
		let ctx = context()
		ctx.speech?.append(CapturedUtterance(text: "background chatter"))
		let mark = try index(ctx)
		#expect(mark == 2)
		// The whole point: reading from the mark cannot return what was said
		// before it, which is what makes an assertion race-free.
		ctx.speech?.append(CapturedUtterance(text: "the answer"))
		#expect(ctx.speech?.entriesSince(mark).entries.map(\.utterance.text) == ["the answer"])
	}

	@Test("on an untouched session the mark is 1, past the sentinel")
	func theFirstBookmark() throws {
		#expect(try index(context()) == 1)
	}
}
