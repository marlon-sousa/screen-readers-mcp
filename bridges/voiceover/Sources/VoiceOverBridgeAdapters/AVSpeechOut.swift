// ROLE: leaf adapter that implements the SpeechOut seam over AVFoundation.
// BUILT BY: Wiring, once per process.
// USED BY: SynthesizerAnnouncer.
// Never build it in a test: a real synthesizer talks over the developer.
// One synthesizer for the process's life, because one that goes out of scope stops speaking mid-sentence.

import AVFoundation

public final class AVSpeechOut: SpeechOut {
	private let synthesizer = AVSpeechSynthesizer()

	public init() {}

	public func speak(_ text: String, voiceIdentifier: String?) throws {
		let utterance = AVSpeechUtterance(string: text)
		if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
			utterance.voice = voice
		}
		synthesizer.speak(utterance)
	}
}
