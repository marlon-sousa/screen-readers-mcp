// ROLE: adapter -- IMPLEMENTS the SessionSignals domain port. It decides what
// the four cues sound like, whether the human has asked for them at all, and
// which of them carry words.
//
// BUILT BY: Wiring, once per process. USED BY: the Session controller, through
// the port -- once when a session establishes, once on the way out, and twice
// more if the silence cap fires. HOLDS: the Tones seam, the Announcer port and
// the BridgeConfig port.
//
// IT REPLACES A PRINTING STUB, and that is this entry's half of a promise 13.4
// made: `BridgeListener` prints its cues because a launcher is watched from a
// terminal, and the port's header has said since then that the real audible one
// arrives with the control dialog. It does, along with the preference that turns
// it off.
//
// THE TONES ARE OUTSIDE VOICEOVER, LIKE THE WORDS. Both halves have to be
// audible while a silent session is holding the reader quiet -- which on this
// platform is rendered inside the capture voice -- so the tones go to the audio
// device directly and the words go through the Announcer, which speaks with the
// bridge's own synthesizer. A cue routed through the reader would be the one
// thing the human cannot hear.
//
// WHY A START CUE CARRIES WORDS AND AN END CUE DOES NOT. The tones say that
// something has taken the reader; they cannot say what it is STANDING IN FOR,
// and the person sitting there deserves to know which (spec 0029). Releasing
// control raises no such question: two descending tones say all there is to say,
// and a sentence at the end of every session would be noise the tenth time.
//
// THE SWITCH IS READ ON EVERY CUE rather than at construction, so turning the
// cues off in the dialog takes effect on the session that is running rather than
// on the next one. `cuesEnabled` silences all four, including the silence cap's
// warning -- the LIFT still happens on time, because the lift is the guarantee
// and the cue is the courtesy (protocol.md §6.1).

import VoiceOverBridgeDomain

public final class AudibleSessionSignals: SessionSignals {
	/// The four cues, as frequencies in hertz. Named rather than inline so the
	/// pairs are visibly each other's opposite -- taking control rises, releasing
	/// it falls -- which is the whole of what a listener has to learn.
	enum Cue {
		static let taken: [Double] = [660, 880]
		static let released: [Double] = [880, 660]
		/// Low and insistent, and deliberately not a member of the pair above: it
		/// is not about control changing hands.
		static let warning: [Double] = [440, 440]
		/// Rising, like taking control, because something is being given back.
		static let lifted: [Double] = [660, 990]
		/// Short enough not to be in the way, long enough to be heard as a tone
		/// rather than a click.
		static let seconds: Double = 0.09
	}

	private let tones: any Tones
	private let announcer: any Announcer
	private let config: any BridgeConfig

	public init(tones: any Tones, announcer: any Announcer, config: any BridgeConfig) {
		self.tones = tones
		self.announcer = announcer
		self.config = config
	}

	public func sessionStarted(persona: String) throws {
		guard config.cuesEnabled else { return }
		try tones.play(Cue.taken, seconds: Cue.seconds)
		let stance = persona.trimmingCharacters(in: .whitespacesAndNewlines)
		try announcer.announce(
			stance.isEmpty
				? "screen reader testing session started"
				: "screen reader testing session started, as \(stance)")
	}

	public func sessionEnded() throws {
		guard config.cuesEnabled else { return }
		try tones.play(Cue.released, seconds: Cue.seconds)
	}

	public func silenceWarning() throws {
		guard config.cuesEnabled else { return }
		try tones.play(Cue.warning, seconds: Cue.seconds)
		// SPOKEN, not only sounded: protocol.md §6.1 asks for a warning to the
		// human, and a tone cannot say that their machine is about to come back.
		try announcer.announce("your machine has been quiet for a while, and is about to speak again")
	}

	public func silenceLifted() throws {
		guard config.cuesEnabled else { return }
		try tones.play(Cue.lifted, seconds: Cue.seconds)
	}
}
