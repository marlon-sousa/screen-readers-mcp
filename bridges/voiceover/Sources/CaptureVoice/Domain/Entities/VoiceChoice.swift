// ROLE: entity -- PROCESSING. Which ordinary voice re-speaks this utterance.
//
// Pure, and pure on purpose: it takes VALUES -- the language asked for, the
// language the system is speaking, the system's default voice for a language,
// and every voice that exists -- and returns one of them. CaptureController does
// the two lookups against the VoiceCatalogue port and hands the results here, so
// every rule below is a test with no fake and no audio device.
//
// This is where the Arabic-reading-Portuguese bug is a test. FOUR rules -- rule
// 0 added by 13.6, and rules 1 to 3 each of which cost a live round against a
// real reader to find (spec 0041, C4):
//
//  0. THE USER'S OWN VOICE, WHEN THE BRIDGE NAMED ONE. The bridge reads the
//     voice the user chose before it points the reader at ours, because that is
//     what it restores at teardown -- so it already holds the value, and handing
//     it over costs one field on the marker channel. The effect is the point: in
//     an attended session pass-through becomes acoustically INVISIBLE rather
//     than a substitute voice nobody asked for (spec 0046, "Rule 0"). It
//     DEGRADES rather than assumes -- a preferred voice this machine cannot
//     resolve falls through to the three below -- and it takes only the voice's
//     IDENTITY, never its rate or pitch, which VoiceOver has already encoded
//     into the SSML as <prosody> (spec 0041, A2); applying both would double
//     them.
//
//  1. NEVER OURS, AND IT STILL WINS OVER RULE 0. Re-speaking with our own voice
//     asks us to synthesize our own output forever -- and the case is REACHABLE
//     rather than theoretical: a session that died without restoring leaves OUR
//     voice as the one the user is "on", so the next session would read it as
//     the preferred one. The suffix exclusion therefore applies to the preferred
//     voice exactly as it does to the fallbacks. Excluded by IDENTIFIER SUFFIX
//     rather than by naming an
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

	/// `preferred` is the catalogue's answer for the voice the bridge named on
	/// the marker channel -- rule 0, and nil whenever the bridge named none or
	/// this machine cannot resolve it. `languageDefault` is the catalogue's
	/// answer for `effectiveLanguage`;
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
		preferred: AvailableVoice? = nil,
		languageDefault: AvailableVoice?,
		candidates: @autoclosure () -> [AvailableVoice]
	) -> AvailableVoice? {
		// Rule 0, and it is checked FIRST so the common path answers before the
		// autoclosure is ever called -- which is the same measurement rule 2's
		// ordering is built on.
		if let preferred, !isOurs(preferred) { return preferred }
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
