// ROLE: adapter seam -- the accepting edge: a bound endpoint that yields one
// connection at a time.
//
// NOT A DOMAIN PORT: the domain runs ONE session over a channel and never learns
// how connections arrive, so this lives with the adapters that use it.
//
// USED BY: BridgeServer, whose accept loop turns each connection into a Session.
// IMPLEMENTED BY: LocalSocketListener and TCPListener; FakeListener
// (Tests/Fakes), which scripts connections and faults.
//
// THE CONTRACT MIRRORS Transport.receive ON PURPOSE: `accept` blocks only up to
// a poll window and throws `PollTimeout` when idle, so the accept loop keeps
// checking whether it should stop, and `close` from another thread makes a
// blocked accept fail rather than hang.

/// The listener has been closed; accepting is over.
///
/// Its own type in the file of the seam that throws it, the same rule that puts
/// `ChannelClosed` beside `MessageChannel`.
public struct ListenerClosed: Error {
	public init() {}
}

public protocol Listener: AnyObject {
	/// The human-readable accepting address -- a socket path, or `host:port`.
	/// Defined once `open()` has bound; it is what a status display shows.
	var endpoint: String { get }

	/// Bind and start listening. Throws on a bind failure, on the CALLER's
	/// thread, so a busy port or an unwritable directory is reported to whoever
	/// asked for the bridge rather than dying inside a thread.
	func open() throws

	/// The next connection. Throws `PollTimeout` when none arrived within the
	/// poll window, and `ListenerClosed` once `close()` has been called.
	func accept() throws -> any Transport

	/// Stop listening. Idempotent, and it unblocks a pending `accept`.
	func close()
}
