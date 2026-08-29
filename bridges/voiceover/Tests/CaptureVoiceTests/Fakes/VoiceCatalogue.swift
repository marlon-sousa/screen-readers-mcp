// A hand-written stateful fake for the VoiceCatalogue port, mirroring
// Sources/CaptureVoice/Domain/Ports/VoiceCatalogue.swift.
//
// `defaultVoice(for:)` is a SEPARATE table from `allVoices()` on purpose, exactly
// as on the real machine: the system's default for a language is not merely the
// first listed voice matching it, and the difference is what stops us choosing a
// listed voice that then fails to synthesize.

@testable import CaptureVoice

final class FakeVoiceCatalogue: VoiceCatalogue {
	var currentLanguage: String
	var defaults: [String: AvailableVoice]
	var voices: [AvailableVoice]
	private(set) var defaultLookups: [String] = []

	init(
		currentLanguage: String = "en-US",
		defaults: [String: AvailableVoice] = [:],
		voices: [AvailableVoice] = []
	) {
		self.currentLanguage = currentLanguage
		self.defaults = defaults
		self.voices = voices
	}

	func defaultVoice(for language: String) -> AvailableVoice? {
		defaultLookups.append(language)
		return defaults[language]
	}

	func allVoices() -> [AvailableVoice] { voices }
}
