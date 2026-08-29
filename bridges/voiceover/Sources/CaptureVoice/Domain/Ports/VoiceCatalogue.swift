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

	/// Everything else, for when the default is ours or absent.
	func allVoices() -> [AvailableVoice]
}
