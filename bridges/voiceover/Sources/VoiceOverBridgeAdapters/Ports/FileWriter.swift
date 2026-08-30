// ROLE: adapter seam -- append lines to a file.
//
// NOT A DOMAIN PORT: the domain has no idea the transcript is a file at all.
//
// USED BY: FileTranscript, which owns the transcript's VOCABULARY and delegates
// every actual write here.
// IMPLEMENTED BY: TextFileWriter (a leaf: real open, write, flush) and
// FakeFileWriter (Tests/Fakes), which records the lines in memory.
//
// This split is what makes the transcript adapter precisely testable: its test
// asserts the exact lines produced without touching a filesystem, and the only
// untestable code left is a leaf that makes no decisions.
public protocol FileWriter: AnyObject {
	/// Where the lines land.
	var path: String { get }

	func open() throws

	/// Append one line, flushed.
	///
	/// PER-LINE FLUSHING IS A REQUIREMENT, not a tuning detail: a crashed harness
	/// must not lose the tail of the transcript, which is the only record a
	/// silent run leaves. Best effort -- a failed write must never throw, because
	/// a broken log must never take down a session.
	func writeLine(_ text: String)

	func close()
}
