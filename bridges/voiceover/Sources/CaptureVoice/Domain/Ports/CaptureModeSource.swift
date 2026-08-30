// ROLE: port -- what has the bridge asked of this utterance: silence or speech,
// and in whose voice?
//
// Implemented by MarkerFileCaptureModeSource (the marker file entry 13.6
// writes); held by CaptureController, which asks it once per utterance rather
// than caching, because the bridge may lift silence between two utterances and
// the lift must take effect on the next one.
//
// SILENCE IS OPT-IN, AND THAT IS AN INVARIANT RATHER THAN A DEFAULT. On this
// route the provider IS the voice: rendering silence leaves the machine's owner
// unable to hear their own computer. So "no marker" means "speak", and every
// adapter of this port must answer `passThrough` when it cannot tell.
//
// ONE VALUE, NOT TWO PROPERTIES, and that is 13.6's amendment to this port. The
// bridge now has a second thing to say -- WHICH voice pass-through should
// re-speak with (spec 0046, "Rule 0") -- and it says it over the same channel,
// because a marker that answered two questions in two reads could be refreshed
// between them and answer about two different sessions. One read, one answer.

/// What the bridge is asking for right now.
public struct CaptureDirective: Equatable, Sendable {
	/// Whether the human is to be kept from hearing this utterance.
	public let silent: Bool

	/// The voice the user chose for themselves, as the bridge read it at session
	/// start -- so pass-through can re-speak in it and be acoustically invisible
	/// (spec 0046, Rule 0). Nil means the bridge did not say, which is the normal
	/// answer when no session is running, and rules 1-3 then choose.
	public let preferredVoice: String?

	public init(silent: Bool, preferredVoice: String? = nil) {
		self.silent = silent
		self.preferredVoice = preferredVoice
	}

	/// THE SAFE ANSWER, and the one every adapter must give when the question
	/// cannot be answered: speak, in whichever voice the rules pick.
	public static let passThrough = CaptureDirective(silent: false, preferredVoice: nil)
}

public protocol CaptureModeSource {
	var directive: CaptureDirective { get }
}
