// ROLE: adapter seam -- say these words on this machine, in this voice.
//
// NOT A DOMAIN PORT: the domain asks for the human to be told something
// (`Announcer`) and does not know that speaking involves a synthesizer, a voice
// identifier, or an utterance object.
//
// IMPLEMENTED BY: AVSpeechOut (a leaf) and FakeSpeechOut (Tests/Fakes).
// USED BY: SynthesizerAnnouncer, which is the one place that decides WHICH voice
// and therefore the one place there is anything to test.
//
// THE SEAM EXISTS BECAUSE NO TEST MAY SPEAK. A real `AVSpeechSynthesizer` in a
// test talks over the developer -- the same class of mistake as typing into
// their frontmost window, and the reason `EventPoster` is a seam too. Everything
// above this line is exercised against a fake; everything below it is fifteen
// lines that make no decisions.

public protocol SpeechOut: AnyObject {
	/// Speak `text` now, with the voice identified by `voiceIdentifier`, or with
	/// whatever the system would choose when that is nil.
	///
	/// It does not wait for the words to finish. `announce` promises that the
	/// bridge SPOKE, never that anybody listened (protocol.md §5), and a handler
	/// that blocked until the audio ended would hold the session thread for as
	/// long as the sentence.
	func speak(_ text: String, voiceIdentifier: String?) throws
}
