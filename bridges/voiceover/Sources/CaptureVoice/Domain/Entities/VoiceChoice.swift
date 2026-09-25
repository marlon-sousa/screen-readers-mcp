// ROLE: entity that picks which ordinary voice re-speaks an utterance, from values the controller looked up.
// 0. The user's own voice when the bridge named one, by identity only: the SSML already carries rate and pitch.
// 1. Never ours, even as the preferred voice: a session that died without restoring leaves ours selected.
// 2. The language's default voice before any listed one; see VoiceCatalogue.
// 3. The system language when the utterance states none: the first listed voice read Portuguese in Arabic.

public struct VoiceChoice: Equatable, Sendable {
	public let effectiveLanguage: String
	public let ourIdentifierSuffix: String

	public init(requestedLanguage: String?, systemLanguage: String, ourIdentifierSuffix: String) {
		self.effectiveLanguage = requestedLanguage ?? systemLanguage
		self.ourIdentifierSuffix = ourIdentifierSuffix
	}

	/// nil only when every voice is ours, which the caller must report by name. `candidates` is an autoclosure:
	/// enumerating 191 voices on macOS 15 put the first sample at 0.380 s instead of 0.218 s.
	public func resolve(
		preferred: AvailableVoice? = nil,
		languageDefault: AvailableVoice?,
		candidates: @autoclosure () -> [AvailableVoice]
	) -> AvailableVoice? {
		if let preferred, !isOurs(preferred) { return preferred }
		if let languageDefault, !isOurs(languageDefault) { return languageDefault }
		let usable = candidates().filter { !isOurs($0) }
		if let exact = usable.first(where: { $0.language == effectiveLanguage }) { return exact }
		let subtag = String(effectiveLanguage.prefix(2))
		return usable.first { $0.language.hasPrefix(subtag) } ?? usable.first
	}

	func isOurs(_ voice: AvailableVoice) -> Bool {
		voice.identifier.hasSuffix(ourIdentifierSuffix)
	}
}
