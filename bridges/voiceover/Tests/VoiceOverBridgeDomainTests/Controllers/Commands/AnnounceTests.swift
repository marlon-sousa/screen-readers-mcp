// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/Announce.swift.
//
// ONE PROPERTY CARRIES THIS FILE, and it is the promise 13.10 exists to make
// keepable: `announce` REACHES THE HUMAN IN A SILENT SESSION. What a unit test
// can check is that the words go to the Announcer -- the channel that speaks with
// the bridge's own synthesizer, outside VoiceOver -- in both modes, identically.
// That it is AUDIBLE on a real machine is a claim no test can make, and
// `scripts/voiceover_announce.sh` is the re-runnable instrument that does.
//
// NO TEST HERE SPEAKS. FakeAnnouncer stands in for the synthesizer, exactly as
// FakeEventPoster stands in for the window server: a test that reached the real
// one would talk over the developer while they read the failure.

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
		// The whole point of the port: the channel goes around the reader, so the
		// mode that mutes the reader changes nothing about it. Before 13.10 this
		// command did not exist and the same words on a `pressGesture` were REFUSED
		// in silent mode, because there was no channel to say them on.
		for mode in [CaptureMode.silent, .live] {
			let announcer = FakeAnnouncer()
			_ = try handler.execute(context(mode: mode, announcer: announcer), request("still here"))
			#expect(announcer.spoken == ["still here"])
		}
	}

	@Test("it is recorded in the transcript, in full, which `typed` deliberately is not")
	func itIsRecorded() throws {
		// An announcement is written to be heard out loud in a room; a password is
		// not. That asymmetry is the reason `announced` takes a string and `typed`
		// takes a length.
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
		// protocol.md §6.1: only sound the human HEARS resets the cap. Four hundred
		// gestures reset nothing; this is one of the three things that do.
		let clock = FakeClock()
		let session = context(clock: clock)
		session.silenceCap = SilenceCap(policy: .attendedDefault, now: clock.monotonic())
		clock.advance(defaultWarnAfter + 1)
		_ = try handler.execute(session, request("you are not alone"))
		#expect(session.silenceCap?.check(clock.monotonic()) == SilenceCapAction.none)
	}

	@Test("it does not MUTATE the reader, so an observe-only session may narrate")
	func itIsNotAMutation() {
		// A decision rather than a default: `announce` changes what the human hears
		// and nothing about the machine under test, and an observe-only session
		// (spec 0017) is exactly the one that should be able to narrate.
		#expect(!handler.mutatesReader)
	}
}
