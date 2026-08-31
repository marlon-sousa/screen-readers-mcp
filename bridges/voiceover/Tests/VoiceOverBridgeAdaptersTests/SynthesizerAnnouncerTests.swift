// Mirrors Sources/VoiceOverBridgeAdapters/SynthesizerAnnouncer.swift.
//
// ONE DECISION, AND IT IS THE ONE THAT COULD FAIL SILENTLY: which voice. If the
// announcer ever picked OUR capture voice, the announcement would go into the
// extension that is rendering silence and the call would return `ok` while the
// room stayed quiet -- in the one mode where `announce` is the human's only
// channel. So the exclusion is asserted first, and asserted as a SUFFIX match,
// because the system publishes our voice as the extension's bundle id followed
// by the one the audio unit declared (spec 0041 A1).
//
// NO TEST HERE SPEAKS: FakeSpeechOut stands in for the synthesizer.

import Fakes
import Testing
import VoiceOverBridgeDomain

@testable import VoiceOverBridgeAdapters

@Suite("SynthesizerAnnouncer")
struct SynthesizerAnnouncerTests {
	/// What the system actually publishes for us, from spec 0047's finding 17: the
	/// extension's bundle id, then ours.
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
		// Nil hands the choice to the system, which is the only remaining option --
		// and still not our voice unless a human has made it their system default.
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
		// A PREFERENCE, NEVER A REQUIREMENT: identifiers are opaque strings that
		// happen to carry a locale, so matching them is a heuristic and it must
		// never be worth failing over.
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
		// The machine's list is a property of the machine, so asking it twice would
		// pay a framework enumeration for an answer that cannot have changed -- and
		// an announcement in a different voice each time is worse to listen to than
		// one in the wrong voice.
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
