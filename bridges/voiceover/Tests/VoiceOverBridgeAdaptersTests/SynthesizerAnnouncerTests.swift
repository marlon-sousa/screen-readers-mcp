// Mirrors Sources/VoiceOverBridgeAdapters/SynthesizerAnnouncer.swift.

import Fakes
import Testing
import VoiceOverBridgeDomain

@testable import VoiceOverBridgeAdapters

@Suite("SynthesizerAnnouncer")
struct SynthesizerAnnouncerTests {
	/// The identifier the system publishes for the capture voice: the extension's bundle id, then the audio unit's.
	private let ours = "org.screen-readers-mcp.spike.capture.voice.org.screen-readers-mcp.spike.capture"

	private func announcer(
		voices: [String],
		out: FakeSpeechOut,
		language: String = "pt-BR"
	) -> SynthesizerAnnouncer {
		SynthesizerAnnouncer(
			voices: FakePublishedVoices(voices: voices),
			out: out,
			excludingSuffix: captureVoiceIdentifierSuffix,
			preferredLanguage: language
		)
	}

	@Test("OUR OWN VOICE IS NEVER CHOSEN -- silence would otherwise talk to itself")
	func itExcludesTheCaptureVoice() throws {
		let out = FakeSpeechOut()
		try announcer(voices: [ours, "com.apple.voice.compact.pt-BR.Luciana"], out: out)
			.announce("hello")
		#expect(out.spoken.first?.voice == "com.apple.voice.compact.pt-BR.Luciana")
	}

	@Test("even when ours is the only thing published, it is not chosen")
	func itNeverFallsBackToOurs() throws {
		let out = FakeSpeechOut()
		try announcer(voices: [ours], out: out).announce("hello")
		#expect(out.spoken.first?.voice == nil)
	}

	@Test("the human's own language is preferred, because a warning nobody parses is not one")
	func itPrefersTheLanguage() throws {
		let out = FakeSpeechOut()
		try announcer(
			voices: [
				"com.apple.voice.compact.en-US.Samantha",
				"com.apple.voice.compact.pt-BR.Luciana",
			], out: out
		).announce("hello")
		#expect(out.spoken.first?.voice == "com.apple.voice.compact.pt-BR.Luciana")
	}

	@Test("a base-language match is second best, and any voice is better than none")
	func itDegradesRatherThanFailing() {
		#expect(
			SynthesizerAnnouncer.choose(
				from: ["com.apple.voice.compact.pt-PT.Joana"], excluding: "x", preferring: "pt-BR")
				== "com.apple.voice.compact.pt-PT.Joana")
		#expect(
			SynthesizerAnnouncer.choose(
				from: ["com.acme.robot"], excluding: "x", preferring: "pt-BR") == "com.acme.robot")
		#expect(SynthesizerAnnouncer.choose(from: [], excluding: "x", preferring: "pt-BR") == nil)
	}

	@Test("the voice is resolved ONCE and kept, so every announcement sounds the same")
	func theChoiceIsStable() throws {
		let voices = FakePublishedVoices(voices: ["com.apple.voice.compact.pt-BR.Luciana"])
		let out = FakeSpeechOut()
		let subject = SynthesizerAnnouncer(
			voices: voices, out: out, excludingSuffix: captureVoiceIdentifierSuffix,
			preferredLanguage: "pt-BR")
		try subject.announce("one")
		try subject.announce("two")
		#expect(voices.enumerations == 1)
		#expect(out.spoken.map(\.text) == ["one", "two"])
	}

	@Test("a synthesizer that refuses is reported as an AnnouncerError the handler can read")
	func aFailureIsTranslated() {
		let out = FakeSpeechOut()
		out.fails = true
		#expect(throws: AnnouncerError.self) {
			try announcer(voices: ["com.apple.voice.compact.pt-BR.Luciana"], out: out).announce("hello")
		}
	}
}
