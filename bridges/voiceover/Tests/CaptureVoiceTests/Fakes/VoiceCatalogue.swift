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
	/// Counted because enumerating every voice COSTS TIME on a real machine, and
	/// the common path must not pay it. See the test that asserts this is zero.
	private(set) var allVoicesReads = 0

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

	func allVoices() -> [AvailableVoice] {
		allVoicesReads += 1
		return voices
	}
}
