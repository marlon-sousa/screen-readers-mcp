// ROLE: adapter seam that says words on this machine, in a given voice.
// IMPLEMENTED BY: AVSpeechOut and FakeSpeechOut.
// USED BY: SynthesizerAnnouncer, which decides which voice.
// No test may speak: a real synthesizer talks over the developer.

public protocol SpeechOut: AnyObject {
	/// A nil `voiceIdentifier` lets the system choose; returns without waiting for the words to finish.
	func speak(_ text: String, voiceIdentifier: String?) throws
}
