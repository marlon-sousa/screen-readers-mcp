// ROLE: adapter seam for what the loopback listener needs the OS to do.
// Not named `TcpBinder`: on a case-insensitive macOS filesystem it would collide with `TCPBinder.swift` and fail at link time.
// USED BY: TCPListener.
// IMPLEMENTED BY: TCPBinder and FakeLoopbackBinder.

public protocol LoopbackBinder: AnyObject {
	/// Binds and listens; answers the port actually bound, which is how a caller asking for port 0 learns it.
	func bind(host: String, port: Int) throws -> Int

	/// The next connection, or `PollTimeout` when idle.
	func accept() throws -> any Transport

	func close()
}
