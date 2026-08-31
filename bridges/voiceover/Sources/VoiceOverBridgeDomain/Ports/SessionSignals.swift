// ROLE: port -- audible cues for the human at the keyboard, telling them the
// bridge has taken or released control of their screen reader.
//
// IMPLEMENTED BY: AudibleSessionSignals (adapters), over the Tones seam and the
// Announcer port; `ReportingSignals` in the launcher, which prints each cue and
// passes it on; FakeSessionSignals (Tests/Fakes).
// USED BY: the Session controller -- once, when a session establishes, and once
// on the way out.
//
// THE REAL ONE ARRIVED AT 13.10, with the human channel that gives it words: the
// tones say control was taken and the Announcer says what it was taken AS, both
// outside VoiceOver, because a cue routed through a reader this session has muted
// is the one thing the human cannot hear. `BridgeConfig.cuesEnabled` is the
// preference that silences them, read on every cue rather than at construction.
//
// BOTH CUES CAN FAIL, AND THE TYPE SAYS SO. In Python a port that raises looks
// exactly like one that does not, so lane 1 wraps every teardown step in a
// blanket guard. Swift makes the claim checkable: a method that may fail is
// `throws`, and the session then guards exactly those and nothing else. A cue is
// a courtesy -- it reaches an audio device that may be gone -- so it is never
// worth a session, and this is where that promise is written down.
//
// TONES, NOT THE ORDINARY SPEECH PATH, and that is the whole point: they have to
// be heard while speech is being suppressed. On macOS the suppression happens
// inside the capture voice (13.6), so a cue spoken through the reader would be
// the one thing the human cannot hear.
public protocol SessionSignals: AnyObject {
	/// Control taken, and what it was taken AS.
	///
	/// The tones say that something has taken the reader; they cannot say what it
	/// is standing in for, and the person sitting there deserves to know which.
	/// `persona` is announced as received -- an implementation does not have to
	/// recognise a value in order to say it. Empty means the server declared none.
	func sessionStarted(persona: String) throws

	/// Control released.
	func sessionEnded() throws

	/// The human has not heard their machine for a while, and the cap is about to
	/// give it back (protocol.md §6.1).
	///
	/// A COURTESY, AND THE LIFT IS THE GUARANTEE. If this cue cannot be played the
	/// session carries on and the lift still happens on time -- which is why it
	/// throws like the other two rather than being allowed to take a session down.
	func silenceWarning() throws

	/// Silence has just been lifted: the machine is audible again.
	///
	/// AUDIBLY MARKED BECAUSE §6.1 SAYS SO -- a human whose machine goes quiet
	/// again later is entitled to have heard it come back in between, or the two
	/// windows read as one long silence.
	func silenceLifted() throws
}
