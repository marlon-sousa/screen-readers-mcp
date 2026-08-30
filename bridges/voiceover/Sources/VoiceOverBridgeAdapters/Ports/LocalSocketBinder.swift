// ROLE: adapter seam -- everything the local endpoint's listener needs the OS to
// do, and nothing it needs the OS to DECIDE.
//
// AN AMENDMENT TO SPEC 0046's 13.4 LAYOUT, with its why: the table names
// `UnixSocketBinder.swift` as a leaf adapter and gives it no seam to implement.
// A leaf implements something -- that is what makes the layer above it testable
// -- so this is that something. The split is exactly the one AGENTS.md
// prescribes: the DECISIONS (protocol.md §1's three listener obligations, their
// order, and what a failure in each of them means) live in LocalSocketListener
// and are unit-tested against a fake binder; the leaf below makes none of them.
//
// The filesystem verbs are here rather than in a seam of their own because on
// POSIX a listening socket IS a file: creating its directory, unlinking it and
// binding to it are three calls about one object, and splitting them across two
// seams would mean two fakes to say one thing.
//
// USED BY: LocalSocketListener. IMPLEMENTED BY: UnixSocketBinder (leaf) and
// FakeLocalSocketBinder (Tests/Fakes).

public protocol LocalSocketBinder: AnyObject {
	/// Create `path` and any missing parent, with permissions `mode`. Succeeds
	/// quietly when it already exists.
	func createDirectory(at path: String, mode: Int) throws

	/// Delete `path` if it is there. Best effort: a socket file that is already
	/// gone is the outcome this is asked for.
	func removeFile(at path: String)

	/// Bind to `path` and start listening.
	func bind(to path: String) throws

	/// The next connection, or `PollTimeout` when idle.
	func accept() throws -> any Transport

	func close()
}
