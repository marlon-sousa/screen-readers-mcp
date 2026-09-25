// ROLE: entity, one thing VoiceOver asked to say, before any audio exists.
// The sequence restarts whenever the system relaunches the extension, so the bridge must not use it as an index.

public struct Utterance: Equatable, Sendable {
	public let sequence: Int
	public let document: SsmlDocument
	public let requestingVoice: String

	public init(sequence: Int, ssml: String, requestingVoice: String) {
		self.sequence = sequence
		self.document = SsmlDocument(ssml)
		self.requestingVoice = requestingVoice
	}

	public var ssml: String { document.source }
	public var text: String { document.text }
	public var language: String? { document.language }
}
