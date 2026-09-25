// ROLE: port -- audible cues telling the human the bridge has taken or released control of their screen reader.
// IMPLEMENTED BY: AudibleSessionSignals, over the Tones seam and the Announcer port; ReportingSignals in the launcher; FakeSessionSignals.
// USED BY: the Session controller, once when a session establishes and once on the way out.
// A cue is a courtesy and never worth a session, so the Session guards every throwing cue.
// Cues play outside VoiceOver, because the suppression happens inside the capture voice.
public protocol SessionSignals: AnyObject {
	/// `persona` is announced as received; empty means the server declared none.
	func sessionStarted(persona: String) throws

	func sessionEnded() throws

	func silenceWarning() throws

	func silenceLifted() throws

	func silenceResuppressed() throws
}
