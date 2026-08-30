// ROLE: port -- audible cues for the human at the keyboard, telling them the
// bridge has taken or released control of their screen reader.
//
// IMPLEMENTED BY: FakeSessionSignals today (Tests/Fakes); the real macOS cue
// adapter arrives with the control dialog (13.10), which is also where the
// on/off preference lives.
// USED BY: the Session controller -- once, when a session establishes, and once
// on the way out.
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
}
