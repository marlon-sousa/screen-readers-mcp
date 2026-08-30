// ROLE: entity -- PROCESSING. Which ordinary voice re-speaks this utterance.
//
// Pure, and pure on purpose: it takes VALUES -- the language asked for, the
// language the system is speaking, the system's default voice for a language,
// and every voice that exists -- and returns one of them. CaptureController does
// the two lookups against the VoiceCatalogue port and hands the results here, so
// every rule below is a test with no fake and no audio device.
//
// This is where the Arabic-reading-Portuguese bug is a test. Three rules, each
// of which cost a live round against a real reader to find (spec 0041, C4):
//
//  1. NEVER OURS. Re-speaking with our own voice asks us to synthesize our own
//     output forever. Excluded by IDENTIFIER SUFFIX rather than by naming an
//     Apple voice that may not exist on someone else's machine -- and by suffix
//     because the system publishes our identifier prefixed with the extension's
//     bundle id, so it never equals what the unit declared.
//  2. THE LANGUAGE'S DEFAULT VOICE FIRST. `speechVoices()` lists voices that then
//     fail to synthesize; CoreSynthesizer falls back silently and the listener
//     hears the wrong voice while nothing reports an error. The default is the
//     one the machine already uses, so it is known to work here.
//  3. THE SYSTEM'S CURRENT LANGUAGE WHEN THE UTTERANCE DOES NOT SAY. VoiceOver's
//     SSML carries no xml:lang at all, so "unknown" is the normal case. Falling
//     through to "whatever voice is first" is not a harmless default: it picked
//     an Arabic voice and read Portuguese aloud in it.

public struct VoiceChoice: Equatable, Sendable {
	/// The language actually used to choose, after rule 3.
	public let effectiveLanguage: String
	/// The identifier of the voice THIS provider publishes. Anything ending in it
	/// is us, however the system chose to prefix it.
	public let ourIdentifierSuffix: String

	public init(requestedLanguage: String?, systemLanguage: String, ourIdentifierSuffix: String) {
		self.effectiveLanguage = requestedLanguage ?? systemLanguage
		self.ourIdentifierSuffix = ourIdentifierSuffix
	}

	/// `languageDefault` is the catalogue's answer for `effectiveLanguage`;
	/// `candidates` is every voice on the machine. Returns nil only when the
	/// machine has no voice that is not ours, which the caller must report by
	/// name rather than render as silence.
	///
	/// `candidates` IS AN AUTOCLOSURE, AND THAT IS A MEASUREMENT RATHER THAN A
	/// STYLE. Enumerating every voice costs real time -- 191 of them on the
	/// machine this was measured on -- and rule 2 means the common path never
	/// needs the list at all. Taking it eagerly put that cost on EVERY utterance
	/// inside the screen reader: 0.380 s to the first sample against the spike's
	/// 0.218 s, entirely because the spike returned before making the call. This
	/// keeps the rules in one pure place and still only pays for the fallback
	/// when the fallback is reached.
	public func resolve(
		languageDefault: AvailableVoice?,
		candidates: @autoclosure () -> [AvailableVoice]
	) -> AvailableVoice? {
		if let languageDefault, !isOurs(languageDefault) { return languageDefault }
		let usable = candidates().filter { !isOurs($0) }
		if let exact = usable.first(where: { $0.language == effectiveLanguage }) { return exact }
		// A language tag's first two characters are its language subtag, so this
		// is "the same language, some other region" -- pt-PT for pt-BR. Better a
		// different accent than a different language.
		let subtag = String(effectiveLanguage.prefix(2))
		return usable.first { $0.language.hasPrefix(subtag) } ?? usable.first
	}

	func isOurs(_ voice: AvailableVoice) -> Bool {
		voice.identifier.hasSuffix(ourIdentifierSuffix)
	}
}
