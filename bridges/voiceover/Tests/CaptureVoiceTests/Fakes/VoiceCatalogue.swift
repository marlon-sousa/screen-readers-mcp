// `defaultVoice(for:)` is a separate table from `allVoices()`, as on the real machine, where the default is not merely the first listed match.

@testable import CaptureVoice

final class FakeVoiceCatalogue: VoiceCatalogue {
	var currentLanguage: String
	var defaults: [String: AvailableVoice]
	var voices: [AvailableVoice]
	private(set) var defaultLookups: [String] = []
	private(set) var allVoicesReads = 0
	private(set) var identifierLookups: [String] = []

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

	/// Not counted as an enumeration: on the real machine this is a direct lookup.
	func voice(identifier: String) -> AvailableVoice? {
		identifierLookups.append(identifier)
		return voices.first { $0.identifier == identifier }
	}

	func allVoices() -> [AvailableVoice] {
		allVoicesReads += 1
		return voices
	}
}
