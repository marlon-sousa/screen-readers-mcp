// ROLE: adapter seam -- a raw byte pipe, and the signal that its poll window
// elapsed.
//
// NOT A DOMAIN PORT, and the distinction is the one AGENTS.md draws: the domain
// speaks whole messages and never sees bytes, so this interface lives out here
// with the adapters that use it.
//
// USED BY: JsonLinesChannel, which frames messages over it.
// IMPLEMENTED BY: SocketTransport (a leaf over a real file descriptor) and
// FakeTransport (Tests/Fakes), which scripts bytes and timeouts.

import Foundation

/// The poll window elapsed with nothing to report.
///
/// Not a failure: it is what lets a blocked reader hand control back so the
/// session can check its deadlines, and what lets an accept loop notice it has
/// been asked to stop -- without either needing a wakeup pipe. The Listener seam
/// throws this same type for the same reason.
public struct PollTimeout: Error {
	public init() {}
}

public protocol Transport: AnyObject {
	/// The next chunk; EMPTY at end of stream, and `PollTimeout` when idle.
	///
	/// A real socket with a receive timeout already behaves exactly this way,
	/// which is why the leaf below this seam is almost nothing.
	func receive() throws -> Data

	func sendAll(_ data: Data) throws

	func close()
}
