// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/WaitForSpeech.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("WaitForSpeechHandler")
struct WaitForSpeechTests {
	private let clock = FakeClock()

	private func context() -> SessionContext {
		let context = SessionContext(
			clock: clock, transcript: FakeTranscript(), attended: true, close: { _ in }
		)
		context.speech = SpeechBuffer(clock: clock)
		return context
	}

	private func result(_ context: SessionContext, _ params: [String: JSONValue]) throws
		-> WaitForSpeechResult
	{
		let value = try WaitForSpeechHandler().execute(
			context, Request(id: 1, cmd: Command.waitForSpeech.rawValue, params: params)
		)
		return try #require(value as? WaitForSpeechResult)
	}

	@Test("a hit reports the match, its index and the instant it was emitted")
	func aHit() throws {
		let ctx = context()
		ctx.speech?.append(CapturedUtterance(text: "Documents, folder", emittedAt: 1_700_000_005))
		let result = try result(ctx, ["text": .string("folder"), "timeout": .double(5)])
		#expect(result.found)
		#expect(result.index == 1)
		#expect(result.text == "Documents, folder")
		#expect(result.emittedAt == Wallclock.format(1_700_000_005))
	}

	@Test("a miss is a normal result: no words, a fresh bookmark, and NO stamp")
	func aMiss() throws {
		let ctx = context()
		ctx.speech?.append(CapturedUtterance(text: "something else", emittedAt: 1_700_000_005))
		let result = try result(ctx, ["text": .string("never said"), "timeout": .double(5)])
		#expect(!result.found)
		#expect(result.text.isEmpty)
		#expect(result.index == ctx.speech?.nextIndex())
		// Empty, deliberately: there is no instant for speech that never arrived,
		// and reporting "now" would read as a match that happened (spec 0028).
		#expect(result.emittedAt.isEmpty)
	}

	@Test("afterIndex is an INCLUSIVE left edge, so the first utterance an action caused counts")
	func theLeftEdgeIsInclusive() throws {
		let ctx = context()
		ctx.speech?.append(CapturedUtterance(text: "before the mark"))
		let mark = try #require(ctx.speech).nextIndex()
		ctx.speech?.append(CapturedUtterance(text: "after the mark"))
		let hit = try result(
			ctx, ["text": .string("after"), "afterIndex": .int(mark), "timeout": .double(1)]
		)
		#expect(hit.found)
		#expect(hit.index == mark)
		// And the mark really does exclude what came before it.
		let miss = try result(
			ctx, ["text": .string("before"), "afterIndex": .int(mark), "timeout": .double(1)]
		)
		#expect(!miss.found)
	}

	@Test("the wait sleeps the injected clock, so a five-second timeout costs microseconds")
	func timeIsInjected() throws {
		let ctx = context()
		_ = try result(ctx, ["text": .string("never"), "timeout": .double(5)])
		#expect(clock.sleeps.reduce(0, +) >= 5)
	}

	@Test("logPosition is 0, because VoiceOver has no journal to position into")
	func noJournalCoordinate() throws {
		let ctx = context()
		ctx.speech?.append(CapturedUtterance(text: "said"))
		#expect(try result(ctx, ["text": .string("said")]).logPosition == 0)
	}
}
