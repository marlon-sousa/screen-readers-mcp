// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/HumanWarning.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("HumanWarning")
struct HumanWarningTests {
	private func context(
		mode: CaptureMode,
		transcript: FakeTranscript = FakeTranscript(),
		announcer: FakeAnnouncer = FakeAnnouncer(),
		clock: FakeClock = FakeClock()
	) -> SessionContext {
		let context = SessionContext(
			clock: clock, transcript: transcript, attended: true, close: { _ in })
		context.mode = mode
		context.adapters = fakeAdapterSet(mode: mode, announcer: announcer)
		return context
	}

	@Test("a SILENT session's warning IS SPOKEN, which is what 13.10 made keepable")
	func silentIsSpoken() throws {
		let announcer = FakeAnnouncer()
		let transcript = FakeTranscript()
		try HumanWarning.honour(
			context(mode: .silent, transcript: transcript, announcer: announcer),
			"about to type into your window")
		#expect(announcer.spoken == ["about to type into your window"])
		#expect(transcript.announcements == ["about to type into your window"])
	}

	@Test("a LIVE session says exactly the same thing, because the channel is the same")
	func liveIsSpokenToo() throws {
		let announcer = FakeAnnouncer()
		try HumanWarning.honour(
			context(mode: .live, announcer: announcer), "moving to the desktop")
		#expect(announcer.spoken == ["moving to the desktop"])
	}

	@Test("a warning that could not be spoken STOPS the command, and says how to proceed")
	func aFailureToSpeakRefuses() throws {
		let announcer = FakeAnnouncer()
		announcer.fails = true
		do {
			try HumanWarning.honour(context(mode: .silent, announcer: announcer), "about to type a secret")
			Issue.record("expected the warning to refuse when it could not be spoken")
		} catch let error as CommandError {
			#expect(error.description.contains("could not be warned"))
			#expect(error.description.contains("empty"))
			#expect(!error.description.contains("secret"))
		}
	}

	@Test("the silence clock is reset only when the words were actually spoken")
	func itResetsTheSilenceWindowAfterSpeaking() throws {
		let clock = FakeClock()
		let announcer = FakeAnnouncer()
		let spoken = context(mode: .silent, announcer: announcer, clock: clock)
		spoken.silenceCap = SilenceCap(policy: .attendedDefault, now: clock.monotonic())
		clock.advance(defaultWarnAfter + 1)
		try HumanWarning.honour(spoken, "warning you")
		#expect(spoken.silenceCap?.check(clock.monotonic()) == SilenceCapAction.none)

		let silent = context(mode: .silent, announcer: { let a = FakeAnnouncer(); a.fails = true; return a }())
		silent.silenceCap = SilenceCap(policy: .attendedDefault, now: clock.monotonic())
		clock.advance(defaultWarnAfter + 1)
		#expect(throws: CommandError.self) { try HumanWarning.honour(silent, "warning you") }
		#expect(silent.silenceCap?.check(clock.monotonic()) == SilenceCapAction.warn)
	}

	@Test("whitespace is not an announcement, so nothing is spoken and nothing is refused")
	func whitespaceIsAbsence() throws {
		let announcer = FakeAnnouncer()
		let transcript = FakeTranscript()
		try HumanWarning.honour(
			context(mode: .silent, transcript: transcript, announcer: announcer), "  \n ")
		#expect(announcer.spoken.isEmpty)
		#expect(transcript.announcements.isEmpty)
	}

	@Test("an absent announce writes nothing at all, in either mode")
	func absenceIsSilent() throws {
		for mode in [CaptureMode.live, .silent] {
			let announcer = FakeAnnouncer()
			let transcript = FakeTranscript()
			try HumanWarning.honour(context(mode: mode, transcript: transcript, announcer: announcer), "")
			#expect(announcer.spoken.isEmpty)
			#expect(transcript.announcements.isEmpty)
		}
	}
}
