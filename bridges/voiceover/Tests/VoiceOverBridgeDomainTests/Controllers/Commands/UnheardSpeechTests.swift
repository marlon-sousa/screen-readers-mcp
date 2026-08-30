// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/UnheardSpeech.swift.
//
// The property under test is a distinction: "the reader did not say it" and "we
// were never listening to the reader" are the same empty answer, and only one of
// them is about the software under test.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("UnheardSpeech")
struct UnheardSpeechTests {
	private func context(
		state: ProviderState = .published,
		selected: String? = "com.apple.eloquence.pt-BR.Reed",
		captured: [String] = []
	) -> SessionContext {
		let context = SessionContext(
			clock: FakeClock(), transcript: FakeTranscript(), attended: true, close: { _ in })
		context.adapters = fakeAdapterSet(
			providerLifecycle: FakeProviderLifecycle(selected: selected, machineState: state))
		let buffer = SpeechBuffer(clock: FakeClock())
		for text in captured { buffer.append(CapturedUtterance(text: text)) }
		context.speech = buffer
		return context
	}

	@Test("a healthy, capturing session says nothing: the miss is the honest answer")
	func aRealMissIsLeftAlone() throws {
		// Anything captured at all proves the provider is capturing (spec 0047,
		// finding 18), so a later miss is a genuine miss -- and the probe is not
		// even paid for.
		try UnheardSpeech.explain(
			context(selected: "org.screen-readers-mcp.capture.voice", captured: ["olá"]))
	}

	@Test("a session that has heard NOTHING, with the voice selected, names both possibilities")
	func nothingHeardNamesBoth() {
		// The undecidable case: the provider may have died, or VoiceOver may never
		// have offered the voice. Nothing outside the reader separates them, so
		// both are named with both recoveries rather than one being guessed at.
		do {
			try UnheardSpeech.explain(context(selected: "org.screen-readers-mcp.capture.voice"))
			Issue.record("expected the silence to be explained")
		} catch let error as CommandError {
			#expect(error.description.contains(ReaderCondition.providerNotRunning.rawValue))
			#expect(error.description.contains(ReaderCondition.captureVoiceNotOfferedByReader.rawValue))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("a session whose voice is not selected says exactly that, with the fix")
	func notSelectedIsNamed() {
		do {
			try UnheardSpeech.explain(context())
			Issue.record("expected the silence to be explained")
		} catch let error as CommandError {
			#expect(error.description.contains(ReaderCondition.captureVoiceNotSelected.rawValue))
			#expect(error.description.contains("pluginkit"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("it writes the condition into the transcript as well, for the human reading later")
	func itIsWrittenDown() {
		let subject = context()
		try? UnheardSpeech.explain(subject)
		let transcript = subject.transcript as? FakeTranscript
		#expect(transcript?.notes.contains { $0.contains("unheard speech") } == true)
	}

	@Test("before a handshake there is nothing to ask, and asking must not crash")
	func noEdgeIsQuiet() throws {
		let bare = SessionContext(
			clock: FakeClock(), transcript: FakeTranscript(), attended: true, close: { _ in })
		try UnheardSpeech.explain(bare)
	}
}
