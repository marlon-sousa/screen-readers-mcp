// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/GetSpeech.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("GetSpeechHandler")
struct GetSpeechTests {
	private let clock = FakeClock()

	private func context() -> SessionContext {
		let context = SessionContext(
			clock: clock, transcript: FakeTranscript(), attended: true, close: { _ in }
		)
		context.speech = SpeechBuffer(clock: clock)
		return context
	}

	private func request(sinceIndex: Int) -> Request {
		Request(id: 1, cmd: Command.getSpeech.rawValue, params: ["sinceIndex": .int(sinceIndex)])
	}

	private func result(_ context: SessionContext, sinceIndex: Int) throws -> SpeechResult {
		let value = try GetSpeechHandler().execute(context, request(sinceIndex: sinceIndex))
		return try #require(value as? SpeechResult)
	}

	@Test("each utterance crosses as its own entry, carrying the index it occupies")
	func entriesCarryTheirOwnIndex() throws {
		let ctx = context()
		ctx.speech?.append(CapturedUtterance(text: "Documents", emittedAt: 1_700_000_000))
		ctx.speech?.append(CapturedUtterance(text: "folder", emittedAt: 1_700_000_001))
		let result = try result(ctx, sinceIndex: 0)
		#expect(result.entries.map(\.text) == ["Documents", "folder"])
		#expect(result.entries.map(\.index) == [1, 2])
	}

	@Test("the half-open range is reported so the next call resumes from toIndex")
	func theRangeIsHalfOpen() throws {
		let ctx = context()
		ctx.speech?.append(CapturedUtterance(text: "said"))
		let first = try result(ctx, sinceIndex: 0)
		#expect(first.fromIndex == 0)
		#expect(first.toIndex == 2)
		let second = try result(ctx, sinceIndex: first.toIndex)
		#expect(second.entries.isEmpty)
		#expect(second.fromIndex == 2)
	}

	@Test("every entry carries the instant it was emitted, rendered as the contract's stamp")
	func entriesCarryTheirStamp() throws {
		let ctx = context()
		ctx.speech?.append(CapturedUtterance(text: "said", emittedAt: 1_700_000_000))
		let entry = try #require(try result(ctx, sinceIndex: 0).entries.first)
		#expect(entry.emittedAt == Wallclock.format(1_700_000_000))
		#expect(!entry.emittedAt.isEmpty)
	}

	@Test("logPosition is 0, because VoiceOver has no journal to position into")
	func noJournalCoordinate() throws {
		let ctx = context()
		ctx.speech?.append(CapturedUtterance(text: "said", emittedAt: 1_700_000_000))
		#expect(try result(ctx, sinceIndex: 0).entries.allSatisfy { $0.logPosition == 0 })
	}

	@Test("an empty buffer answers with an empty range, not an error")
	func emptyIsAnAnswer() throws {
		let result = try result(context(), sinceIndex: 0)
		#expect(result.entries.isEmpty)
		#expect(result.toIndex == 1)
	}

	@Test("params that are not this command's fail as a validation error naming the field")
	func badParams() {
		let ctx = context()
		#expect(throws: ValidationError.self) {
			try GetSpeechHandler().execute(ctx, Request(id: 1, cmd: "getSpeech", params: [:]))
		}
	}

	@Test("read before hello, it fails with a readable error rather than a crash")
	func withoutABuffer() {
		let ctx = SessionContext(
			clock: clock, transcript: FakeTranscript(), attended: true, close: { _ in }
		)
		#expect(throws: CommandError.self) {
			try GetSpeechHandler().execute(ctx, request(sinceIndex: 0))
		}
	}
}
