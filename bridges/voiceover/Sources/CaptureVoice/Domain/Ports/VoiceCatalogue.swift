// ROLE: port, implemented by AVSpeechVoiceCatalogue: the voices on this machine and the language it speaks.
// On macOS 15 `speechVoices()` lists voices that then fail to synthesize and are silently substituted,
// while the language's default voice is the one the machine already uses and is known to work.

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
	var currentLanguage: String { get }

	func defaultVoice(for language: String) -> AvailableVoice?

	/// A direct lookup that never enumerates the list; nil when this machine has no such voice.
	func voice(identifier: String) -> AvailableVoice?

	func allVoices() -> [AvailableVoice]
}
