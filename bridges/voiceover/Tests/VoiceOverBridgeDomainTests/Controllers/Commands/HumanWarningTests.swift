// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/HumanWarning.swift.
//
// The file exists so that `pressGesture` and `typeText` CANNOT differ about what
// an unhonourable `announce` does, so this suite tests the shared decision once
// and the two handlers' own suites test only that they call it before acting.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("HumanWarning")
struct HumanWarningTests {
	private func context(mode: CaptureMode, transcript: FakeTranscript = FakeTranscript())
		-> SessionContext
	{
		let context = SessionContext(
			clock: FakeClock(), transcript: transcript, attended: true, close: { _ in })
		context.mode = mode
		return context
	}

	@Test("a SILENT session refuses a warning it cannot speak, by name and with a way on")
	func silentRefuses() throws {
		// The one place `announce` is the human's only channel: the reader is being
		// rendered mute on their behalf, so a warning that cannot be honoured is
		// refused rather than dropped.
		do {
			try HumanWarning.honour(context(mode: .silent), "about to type your password")
			Issue.record("expected the warning to be refused")
		} catch let error as CommandError {
			#expect(error.description.contains("announce"))
			#expect(error.description.contains("silent"))
			// A way to proceed deliberately, so an agent is not simply stuck.
			#expect(error.description.contains("empty"))
			// And it must NOT quote the words back: `announce` on a `typeText` is
			// as likely as anything else to describe what is about to be typed.
			#expect(!error.description.contains("password"))
		}
	}

	@Test("a LIVE session notes the warning and lets the command proceed")
	func liveNotesAndProceeds() throws {
		let transcript = FakeTranscript()
		try HumanWarning.honour(context(mode: .live, transcript: transcript), "moving to the desktop")
		#expect(transcript.notes.contains { $0.contains("moving to the desktop") })
		#expect(transcript.notes.contains { $0.contains("not spoken") })
	}

	@Test("whitespace is not an announcement, so even a silent session is not refused over it")
	func whitespaceIsAbsence() throws {
		let transcript = FakeTranscript()
		try HumanWarning.honour(context(mode: .silent, transcript: transcript), "  \n ")
		#expect(transcript.notes.isEmpty)
	}

	@Test("an absent announce writes nothing at all, in either mode")
	func absenceIsSilent() throws {
		for mode in [CaptureMode.live, .silent] {
			let transcript = FakeTranscript()
			try HumanWarning.honour(context(mode: mode, transcript: transcript), "")
			#expect(transcript.notes.isEmpty)
		}
	}
}
