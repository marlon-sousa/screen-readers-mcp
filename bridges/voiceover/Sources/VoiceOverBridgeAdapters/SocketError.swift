// ROLE: supporting construct -- the one place a POSIX `errno` becomes an error a
// human can read.
//
// AN AMENDMENT TO SPEC 0046's 13.4 LAYOUT, with its why: three leaves below this
// module's two listeners call the socket API, and every one of them has to
// report a failure. Left to each of them it would be three spellings of the same
// thing, and the interesting half -- WHICH call failed -- is the half a bare
// errno leaves out. `bind: Address already in use` is a diagnosis; `Error
// Domain=NSPOSIXErrorDomain Code=48` is a search.
//
// USED BY: SocketTransport, UnixSocketBinder, TCPBinder. No test file: it
// renders a number the C library already formatted.

import Foundation

public struct SocketError: Error, CustomStringConvertible {
	/// The call that failed, as it is spelled in the manual page.
	public let call: String
	public let code: Int32

	public var description: String {
		"\(call): \(String(cString: strerror(code)))"
	}

	public init(call: String, code: Int32) {
		self.call = call
		self.code = code
	}

	/// Capture `errno` NOW. It is per-thread but it is also overwritten by the
	/// next failing call, so it is read at the throw site and never later.
	public static func latest(_ call: String) -> SocketError {
		SocketError(call: call, code: errno)
	}
}
