// ROLE: port -- the human-readable record of everything a session did.
//
// IMPLEMENTED BY: FileTranscript (adapters) over the FileWriter seam;
// FakeTranscript (Tests/Fakes), which records the same lines in memory.
// USED BY: the Session controller, which reports each event as it happens, and
// by the hello handler, which hands `logPath` back to the agent.
//
// A silent run is an audio blackout: nobody hears what the reader "said", so
// this file is how a tester reconstructs the run afterwards. It is written
// bridge-side, so it is complete even for speech the agent never fetched.
//
// THE VOCABULARY GROWS ONE ENTRY AT A TIME, and what is missing here is a
// statement rather than an omission: `speech` arrived with the capture feed
// (13.5), `gesture` with input: commands (13.7) and `typed` with input: typing
// (13.8) -- each added by the entry that first produces the event. A transcript
// verb nothing can emit would be a promise this build does not keep.
// NOTHING HERE THROWS, and that is the contract rather than an omission: a
// broken log must never take down a session, still less stop the teardown that
// gives a human their screen reader back. So an implementation swallows its own
// IO failures, exactly as the FileWriter seam beneath it does, and the session
// needs no guard around a call that cannot fail.
public protocol Transcript: AnyObject {
	/// Where the record can be read; returned to the agent at `hello`.
	var logPath: String { get }

	func open()

	/// A session began, and what it is standing in for.
	///
	/// `persona` is spec 0029's declaration, written down because this file is
	/// read AFTERWARDS to work out what a run meant: the same observation is a
	/// pass from one stance and a finding from another.
	func sessionOpened(mode: String, voice: String, persona: String)

	/// One captured utterance, recorded as it arrives.
	///
	/// Wired to the SpeechBuffer's observer by `hello`, so the record is complete
	/// even for speech the agent never fetched -- and it is written on the
	/// capture thread, outside the buffer's lock, which is why an implementation
	/// must not block on anything but its own append.
	func speech(_ text: String)

	/// One command dispatched to the reader, recorded BEFORE it is sent.
	///
	/// Before, not after, and that is the whole reason this verb exists rather
	/// than the handler noting a summary at the end: `pressGesture` mutates the
	/// user's machine, and the question a transcript has to answer is "what was
	/// this run doing when it went wrong?". A command recorded only on success
	/// would leave the one that hung, crashed the reader, or was still in flight
	/// missing from the record -- which is exactly the command anyone reading the
	/// file afterwards is looking for.
	func gesture(_ command: String)

	/// That `length` characters were typed -- NEVER the text itself.
	///
	/// THE OBLIGATION protocol.md §5 PUTS ON THIS FILE. `typeText` is exactly how
	/// a secret is entered, which is why the wire result carries a count rather
	/// than the words; a transcript is a file a human reads afterwards, so a
	/// password written here is a password on disk, outliving the session that
	/// typed it. The length is all the record carries, and it is the same number
	/// the result reports.
	///
	/// Recorded BEFORE the injection, for the reason `gesture` is: the call anyone
	/// reading this file is looking for is the one that went wrong, and a record
	/// written on success would be missing exactly that one.
	func typed(_ length: Int)

	func note(_ text: String)

	func sessionClosed(reason: String)
}
