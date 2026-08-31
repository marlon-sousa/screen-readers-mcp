// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/HumanWarning.swift.
//
// The file exists so that `pressGesture` and `typeText` CANNOT differ about what
// an `announce` does, so this suite tests the shared decision once and the two
// handlers' own suites test only that they call it before acting.
//
// ITS NAMED REFUSAL WAS DELETED HERE AT 13.10, and this comment is the record of
// it. Until the human channel existed, a warning in a SILENT session was refused
// -- because that mode is the one place `announce` is the human's only channel,
// and this bridge does not half-keep a promise about somebody's ears. The
// Announcer speaks outside VoiceOver entirely, so the promise is keepable and the
// refusal went in the same commit that made it so. That is the same move 13.6
// made with `VoiceOverAdapterFactory`'s refusal of a silent session, and it is
// the pattern the bridge's AGENTS.md records.

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
		// The one place `announce` is the human's only channel: the reader is being
		// rendered mute on their behalf, and the Announcer goes around it.
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
		// If this session cannot tell the human what is about to happen to their
		// machine, nothing happens to it. The caller's very next line is the
		// keystroke that would otherwise have gone out unannounced.
		let announcer = FakeAnnouncer()
		announcer.fails = true
		do {
			try HumanWarning.honour(context(mode: .silent, announcer: announcer), "about to type a secret")
			Issue.record("expected the warning to refuse when it could not be spoken")
		} catch let error as CommandError {
			#expect(error.description.contains("could not be warned"))
			// A way to proceed deliberately, so an agent is not simply stuck.
			#expect(error.description.contains("empty"))
			// And it must NOT quote the words back: `announce` on a `typeText` is
			// as likely as anything else to describe what is about to be typed.
			#expect(!error.description.contains("secret"))
		}
	}

	@Test("the silence clock is reset only when the words were actually spoken")
	func itResetsTheSilenceWindowAfterSpeaking() throws {
		// protocol.md §6.1: what resets the cap is sound the human ACTUALLY HEARS.
		// A warning that threw reset nothing, because nothing was said.
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
