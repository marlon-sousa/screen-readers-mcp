// ROLE: port -- the human-readable record of everything a session did.
// IMPLEMENTED BY: FileTranscript, over the FileWriter seam; FakeTranscript.
// USED BY: the Session controller, and the Hello handler, which hands `logPath` to the agent.
// Nothing here throws: an implementation swallows its own IO failures, so a broken log never stops a teardown.
public protocol Transcript: AnyObject {
	var logPath: String { get }

	func open()

	func sessionOpened(mode: String, voice: String, persona: String)

	/// Written on the capture thread, so an implementation must not block on anything but its own append.
	func speech(_ text: String)

	/// Called before the command is sent, so a command that hung stays in the record.
	func gesture(_ command: String)

	/// Records only the length, never the text: typed text may be a secret.
	func typed(_ length: Int)

	func announced(_ text: String)

	func note(_ text: String)

	func sessionClosed(reason: String)
}
