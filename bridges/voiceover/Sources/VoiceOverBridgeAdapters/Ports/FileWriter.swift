// ROLE: adapter seam -- append lines to a file.
// USED BY: FileTranscript and FileChangeJournal.
// IMPLEMENTED BY: TextFileWriter, AppendingTextFileWriter and FakeFileWriter.
public protocol FileWriter: AnyObject {
	var path: String { get }

	func open() throws

	/// Append one line and flush it, so a crash cannot take the tail; never throws, because a broken log must not end a session.
	func writeLine(_ text: String)

	func close()
}
