// Mirrors Sources/CaptureVoice/Domain/Entities/VoiceChoice.swift.
//
// THIS IS WHERE THE ARABIC-READING-PORTUGUESE BUG IS A TEST. It cost a live round
// against the maintainer's own screen reader to find, and until this file existed
// it was a comment.

import Testing

@testable import CaptureVoice

@Suite("VoiceChoice")
struct VoiceChoiceTests {
	static let ourSuffix = "org.screen-readers-mcp.spike.capture"
	/// What the system actually publishes: the extension's bundle id, then ours.
	/// Never equal to the identifier the unit declared, which is why the match is
	/// by suffix.
	static let ourPublished = AvailableVoice(
		identifier: "org.screen-readers-mcp.spike.capture.voice." + ourSuffix,
		name: "Capture Spike",
		language: "pt-BR"
	)
	static let arabic = AvailableVoice(
		identifier: "com.apple.voice.compact.ar-001.Maged", name: "Maged", language: "ar-001")
	static let brazilian = AvailableVoice(
		identifier: "com.apple.voice.compact.pt-BR.Luciana", name: "Luciana", language: "pt-BR")
	static let portuguese = AvailableVoice(
		identifier: "com.apple.voice.compact.pt-PT.Joana", name: "Joana", language: "pt-PT")

	func choice(requested: String?, system: String) -> VoiceChoice {
		VoiceChoice(
			requestedLanguage: requested,
			systemLanguage: system,
			ourIdentifierSuffix: VoiceChoiceTests.ourSuffix
		)
	}

	@Test("with no language stated, the SYSTEM's language decides -- not the first voice listed")
	func systemLanguageIsTheFallback() {
		// The bug, exactly: VoiceOver states no language, the Arabic voice happens
		// to be first, and Portuguese gets read aloud in Arabic.
		let subject = choice(requested: nil, system: "pt-BR")
		#expect(subject.effectiveLanguage == "pt-BR")
		let chosen = subject.resolve(
			languageDefault: nil,
			candidates: [VoiceChoiceTests.arabic, VoiceChoiceTests.brazilian]
		)
		#expect(chosen == VoiceChoiceTests.brazilian)
	}

	@Test("a stated language wins over the system's")
	func statedLanguageWins() {
		let subject = choice(requested: "pt-PT", system: "en-US")
		#expect(subject.effectiveLanguage == "pt-PT")
		#expect(
			subject.resolve(
				languageDefault: nil,
				candidates: [VoiceChoiceTests.brazilian, VoiceChoiceTests.portuguese]
			) == VoiceChoiceTests.portuguese)
	}

	@Test("the language's DEFAULT voice wins over a listed voice that matches")
	func theDefaultIsPreferred() {
		// Not a tie-break: `speechVoices()` lists voices that then fail to
		// synthesize, and the system substitutes another one silently. The default
		// is the voice the machine already uses, so it is known to work here.
		let chosen = choice(requested: "pt-BR", system: "pt-BR").resolve(
			languageDefault: VoiceChoiceTests.brazilian,
			candidates: [VoiceChoiceTests.portuguese, VoiceChoiceTests.arabic]
		)
		#expect(chosen == VoiceChoiceTests.brazilian)
	}

	@Test("OURS is never chosen, even when it is the language's default")
	func ourVoiceIsNeverTheDefault() {
		// If it were, we would be asked to synthesize our own output forever.
		let chosen = choice(requested: "pt-BR", system: "pt-BR").resolve(
			languageDefault: VoiceChoiceTests.ourPublished,
			candidates: [VoiceChoiceTests.ourPublished, VoiceChoiceTests.brazilian]
		)
		#expect(chosen == VoiceChoiceTests.brazilian)
	}

	@Test("OURS is never chosen from the candidates either, however it is prefixed")
	func ourVoiceIsNeverACandidate() {
		let chosen = choice(requested: "pt-BR", system: "pt-BR").resolve(
			languageDefault: nil,
			candidates: [VoiceChoiceTests.ourPublished]
		)
		#expect(chosen == nil)
	}

	@Test("a different region of the same language beats a different language")
	func regionFallsBackToTheLanguageSubtag() {
		let chosen = choice(requested: "pt-BR", system: "pt-BR").resolve(
			languageDefault: nil,
			candidates: [VoiceChoiceTests.arabic, VoiceChoiceTests.portuguese]
		)
		#expect(chosen == VoiceChoiceTests.portuguese)
	}

	@Test("any voice at all beats none -- a wrong accent is better than silence")
	func anythingBeatsNothing() {
		let chosen = choice(requested: "pt-BR", system: "pt-BR").resolve(
			languageDefault: nil,
			candidates: [VoiceChoiceTests.arabic]
		)
		#expect(chosen == VoiceChoiceTests.arabic)
	}

	@Test("nothing to choose from is nil, and the caller must say so by name")
	func noVoicesAtAll() {
		#expect(choice(requested: nil, system: "en-US").resolve(languageDefault: nil, candidates: []) == nil)
	}
}
