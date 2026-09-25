// ROLE: adapter seam that makes a short sound on this machine.
// IMPLEMENTED BY: CoreAudioTones and FakeTones.
// USED BY: AudibleSessionSignals, which decides which sounds mean what and whether the human wants any.
// Throws when the audio device is gone; a cue failure must never end a session.

public protocol Tones: AnyObject {
	/// Plays `frequencies` in order, separated by `gapSeconds` of silence; without the gap two tones are heard as one sound that changes pitch.
	func play(_ frequencies: [Double], seconds: Double, gapSeconds: Double) throws
}
