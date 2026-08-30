// ROLE: adapter seam -- what the loopback listener needs the OS to do.
//
// THE SAME AMENDMENT AS LocalSocketBinder, for the same reason: spec 0046's
// table names `TCPBinder.swift` a leaf adapter without naming what it
// implements, and a leaf implements a seam.
//
// IT IS `LoopbackBinder` AND NOT `TcpBinder`, WHICH IS A REAL CONSTRAINT AND NOT
// A PREFERENCE: macOS filesystems are case-insensitive by default, so
// `TcpBinder.swift` beside `TCPBinder.swift` is ONE file as far as the build is
// concerned -- the object files collide, one silently overwrites the other, and
// the failure arrives as an undefined protocol descriptor at link time with
// nothing pointing at the cause. The name earns its keep anyway: loopback-only
// is this listener's whole rule.
//
// USED BY: TCPListener. IMPLEMENTED BY: TCPBinder (leaf) and FakeLoopbackBinder
// (Tests/Fakes).
//
// `bind` RETURNS THE PORT ACTUALLY BOUND, which is the one thing this seam does
// that its unix counterpart does not need: a caller may ask for port 0 and only
// then learn what it got. Tests use that, and so does a second bridge on one
// machine.

public protocol LoopbackBinder: AnyObject {
	/// Bind to `host`:`port` and start listening; answers the port actually
	/// bound.
	func bind(host: String, port: Int) throws -> Int

	/// The next connection, or `PollTimeout` when idle.
	func accept() throws -> any Transport

	func close()
}
