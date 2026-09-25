// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/Announce.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("Announce")
struct AnnounceTests {
	private let handler = AnnounceHandler()

	private func context(
		mode: CaptureMode = .silent,
		announcer: FakeAnnouncer = FakeAnnouncer(),
		transcript: FakeTranscript = FakeTranscript(),
		clock: FakeClock = FakeClock()
	) -> SessionContext {
		let context = SessionContext(
			clock: clock, transcript: transcript, attended: true, close: { _ in })
		context.mode = mode
		context.adapters = fakeAdapterSet(mode: mode, announcer: announcer)
		return context
	}

	private func request(_ text: String) -> Request {
		Request(id: 1, cmd: Command.announce.rawValue, params: ["text": .string(text)])
	}

	@Test("the words go to the human's channel, and the reply is the plain ack")
	func itSpeaks() throws {
		let announcer = FakeAnnouncer()
		let result = try handler.execute(context(announcer: announcer), request("the agent is typing"))
		#expect(announcer.spoken == ["the agent is typing"])
		#expect((result as? AckResult)?.ok == true)
	}

	@Test("A SILENT SESSION IS ANNOUNCED TO EXACTLY AS A LIVE ONE IS")
	func bothModesReachTheHuman() throws {
		for mode in [CaptureMode.silent, .live] {
			let announcer = FakeAnnouncer()
			_ = try handler.execute(context(mode: mode, announcer: announcer), request("still here"))
			#expect(announcer.spoken == ["still here"])
		}
	}

	@Test("it is recorded in the transcript, in full, which `typed` deliberately is not")
	func itIsRecorded() throws {
		let transcript = FakeTranscript()
		_ = try handler.execute(context(transcript: transcript), request("about to press escape"))
		#expect(transcript.announcements == ["about to press escape"])
	}

	@Test("a failure to speak is an ERROR FRAME, not an ack with a lie in it")
	func aFailureIsReported() throws {
		let announcer = FakeAnnouncer()
		announcer.fails = true
		#expect(throws: CommandError.self) {
			try handler.execute(context(announcer: announcer), request("can you hear this"))
		}
	}

	@Test("whitespace says nothing and succeeds, because nothing was asked for")
	func whitespaceIsNothingToSay() throws {
		let announcer = FakeAnnouncer()
		let transcript = FakeTranscript()
		let result = try handler.execute(
			context(announcer: announcer, transcript: transcript), request("   "))
		#expect(announcer.spoken.isEmpty)
		#expect(transcript.announcements.isEmpty)
		#expect((result as? AckResult)?.ok == true)
	}

	@Test("it resets the silence window, because the human actually heard something")
	func itResetsTheSilenceWindow() throws {
		let clock = FakeClock()
		let session = context(clock: clock)
		session.silenceCap = SilenceCap(policy: .attendedDefault, now: clock.monotonic())
		clock.advance(defaultWarnAfter + 1)
		_ = try handler.execute(session, request("you are not alone"))
		#expect(session.silenceCap?.check(clock.monotonic()) == SilenceCapAction.none)
	}

	@Test("it does not MUTATE the reader, so an observe-only session may narrate")
	func itIsNotAMutation() {
		#expect(!handler.mutatesReader)
	}
}
