// ROLE: adapter seam for the accepting edge, a bound endpoint that yields one connection at a time.
// USED BY: BridgeServer.
// IMPLEMENTED BY: LocalSocketListener, TCPListener and FakeListener.

public struct ListenerClosed: Error {
	public init() {}
}

public protocol Listener: AnyObject {
	/// Human-readable address, a socket path or `host:port`, defined once `open()` has bound.
	var endpoint: String { get }

	/// Throws a bind failure on the caller's thread, so it reaches whoever asked for the bridge.
	func open() throws

	/// Throws `PollTimeout` when idle, and `ListenerClosed` once `close()` has been called.
	func accept() throws -> any Transport

	/// Stop listening. Idempotent, and it unblocks a pending `accept`.
	func close()
}
