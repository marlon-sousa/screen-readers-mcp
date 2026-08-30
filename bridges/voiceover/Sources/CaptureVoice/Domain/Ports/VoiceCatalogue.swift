// ROLE: port -- what voices exist on this machine, and what language it speaks.
//
// Implemented by AVSpeechVoiceCatalogue (a leaf: it calls
// AVSpeechSynthesisVoice and decides nothing). Held by CaptureController, which
// reads it and hands the values to the VoiceChoice entity -- so the DECISION is
// pure and testable and only the LOOKUP is at the edge.
//
// `defaultVoice(for:)` is separate from `allVoices()` and that is load-bearing
// rather than convenience. Measured on macOS 15.0: `speechVoices()` LISTS voices
// that then fail to synthesize, and the system quietly substitutes another one --
// so the provider's stated choice becomes a fiction while the listener hears
// speech and nothing looks wrong. The language's DEFAULT voice is the one the
// machine already uses and is therefore known to work here.

/// A voice this machine can speak with.
public struct AvailableVoice: Equatable, Sendable {
	public let identifier: String
	public let name: String
	public let language: String

	public init(identifier: String, name: String, language: String) {
		self.identifier = identifier
		self.name = name
		self.language = language
	}
}

public protocol VoiceCatalogue {
	/// What the system is speaking right now, as a BCP-47 tag. The honest default
	/// when an utterance does not say -- see VoiceChoice.
	var currentLanguage: String { get }

	/// The system's preferred voice for a language, which is known to work here.
	func defaultVoice(for language: String) -> AvailableVoice?

	/// One voice by identifier, WITHOUT enumerating the list.
	///
	/// Added by 13.6 for Rule 0 (spec 0046): pass-through re-speaks with the
	/// voice the user chose for themselves, and the bridge names it by
	/// identifier. Resolving it through `allVoices()` would pay the 191-voice
	/// enumeration on the COMMON path, which is the cost `resolve`'s autoclosure
	/// exists to avoid; `AVSpeechSynthesisVoice(identifier:)` is a direct lookup.
	/// Nil when this machine has no such voice, which is Rule 0 degrading rather
	/// than assuming.
	func voice(identifier: String) -> AvailableVoice?

	/// Everything else, for when the default is ours or absent.
	func allVoices() -> [AvailableVoice]
}
