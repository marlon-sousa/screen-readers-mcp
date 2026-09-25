// ROLE: adapter seam for everything the local endpoint's listener needs the OS to do, and nothing it needs it to decide.
// USED BY: LocalSocketListener.
// IMPLEMENTED BY: UnixSocketBinder and FakeLocalSocketBinder.

public protocol LocalSocketBinder: AnyObject {
	/// Creates `path` and missing parents with `mode`; succeeds when it already exists.
	func createDirectory(at path: String, mode: Int) throws

	/// Best effort: a file already gone is the outcome asked for.
	func removeFile(at path: String)

	func bind(to path: String) throws

	/// The next connection, or `PollTimeout` when idle.
	func accept() throws -> any Transport

	func close()
}
