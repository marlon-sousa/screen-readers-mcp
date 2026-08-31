// ROLE: LEAF adapter -- IMPLEMENTS the SpeechOut seam over AVFoundation. It
// makes the machine speak and decides nothing.
//
// BUILT BY: Wiring, once per process. USED BY: SynthesizerAnnouncer, which is
// where every decision lives -- which voice, and whether there is anything to
// say at all.
//
// NO TEST FILE, AND HERE THAT IS A HARD RULE RATHER THAN THE USUAL LEAF
// ARGUMENT: a real `AVSpeechSynthesizer` in a test TALKS OVER THE DEVELOPER.
// That is the same class of mistake as typing into whatever window they have in
// front of them, and it is why the seam above exists. Nothing but a bridge
// somebody started deliberately ever builds this class.
//
// ONE SYNTHESIZER, HELD FOR THE PROCESS'S LIFE, and that is not a micro-
// optimisation: an AVSpeechSynthesizer that goes out of scope while it is
// speaking stops speaking, so a local one would produce an announcement that is
// cut off after a word or two -- exactly the announcements that matter least
// being the only ones short enough to survive.
//
// IT DOES NOT WAIT FOR THE WORDS TO FINISH, per the seam's contract: `speak`
// enqueues and returns, so a handler never holds the session thread for the
// length of a sentence.

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
