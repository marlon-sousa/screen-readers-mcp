// ROLE: entity -- INPUT, MADE A VALUE. One thing VoiceOver asked to say, before
// any audio exists.
//
// Pure. Built by CaptureController from what CaptureAudioUnit was handed; passed
// to the Synthesizer port and rendered into a CaptureEvent for the UtteranceSink.
//
// THE SEQUENCE IS PER PROCESS, AND THE HEADER SAYS SO BECAUSE THE NUMBER LOOKS
// TRUSTWORTHY AND IS NOT. The system relaunches this extension freely, and the
// counter restarts when it does. Measured in spec 0041, A4. Entry 13.5's
// SpeechBuffer therefore assigns the bridge's OWN indices and discards these --
// a bridge that trusted them would have its ordering reset without warning.
// They are kept here anyway because they are what tells two byte-identical
// consecutive utterances apart, which is the thing polling `last phrase` cannot
// do (six of 62 utterances in the measured session).

public struct Utterance: Equatable, Sendable {
	public let sequence: Int
	public let document: SsmlDocument
	/// The voice the CLIENT asked for -- ours -- not the one we re-speak with.
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
