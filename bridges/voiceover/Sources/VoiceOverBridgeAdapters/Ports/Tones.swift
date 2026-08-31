// ROLE: adapter seam -- make a short sound on this machine.
//
// NOT A DOMAIN PORT: the domain asks for the human to be told that control was
// taken or released (`SessionSignals`) and knows nothing about frequencies,
// audio engines or sample rates.
//
// IMPLEMENTED BY: CoreAudioTones (a leaf) and FakeTones (Tests/Fakes).
// USED BY: AudibleSessionSignals, which is the one place that decides WHICH
// sounds mean what, and whether the human has asked for any.
//
// TONES RATHER THAN WORDS, AND THE PORT ABOVE SAYS WHY: a cue has to be
// recognisable in a fraction of a second and has to mean the same thing in every
// language. The words that go with a start cue -- what the session is standing
// in for -- travel on the Announcer instead, so this seam stays the one that
// cannot be misheard.
//
// IT THROWS, because it reaches an audio device that may be gone, and a courtesy
// is never worth a session.

public protocol Tones: AnyObject {
	/// Play `frequencies` in order, each for `seconds`. A rising pair and a
	/// falling pair are the whole vocabulary today; the seam takes a list because
	/// "two tones, in this order" is the thing being asked for.
	func play(_ frequencies: [Double], seconds: Double) throws
}
