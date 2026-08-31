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
	/// Play `frequencies` in order, each for `seconds`, separated by `gapSeconds`
	/// of silence. A rising pair and a falling pair are the whole vocabulary
	/// today; the seam takes a list because "two tones, in this order" is the
	/// thing being asked for.
	///
	/// THE GAP IS PART OF WHAT THE CUE IS, which is why it crosses this seam
	/// rather than living in the leaf. Two tones played back to back are heard as
	/// ONE sound that changes pitch; the same two with a short silence between
	/// them are heard as TWO beeps, and "two beeps" is what the cue means. 13.11
	/// added it after the maintainer -- who uses NVDA daily -- reported that this
	/// bridge's cue was "light" where NVDA's is "clear". It was: 90 ms of
	/// continuous tone at a fifth of full scale, against lane 1's two 180 ms beeps
	/// 300 ms apart.
	func play(_ frequencies: [Double], seconds: Double, gapSeconds: Double) throws
}
