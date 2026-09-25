// ROLE: supporting construct turning a POSIX `errno` into an error that names the call that failed.
// USED BY: SocketTransport, UnixSocketBinder and TCPBinder.

import Foundation

public struct SocketError: Error, CustomStringConvertible {
	public let call: String
	public let code: Int32

	public var description: String {
		"\(call): \(String(cString: strerror(code)))"
	}

	public init(call: String, code: Int32) {
		self.call = call
		self.code = code
	}

	/// Read `errno` at the throw site: the next failing call overwrites it.
	public static func latest(_ call: String) -> SocketError {
		SocketError(call: call, code: errno)
	}
}
