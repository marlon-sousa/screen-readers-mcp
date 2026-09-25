// ROLE: leaf adapter implementing the LoopbackBinder seam with the real socket calls.
// USED BY: TCPListener, through the seam.
// SO_REUSEADDR lets a just-stopped bridge rebind a port still in TIME_WAIT.

import Darwin
import Foundation

public final class TCPBinder: LoopbackBinder {
	private var descriptor: Int32 = -1
	private let acceptTimeout: Double
	private let receiveTimeout: Double

	public init(acceptTimeout: Double = 0.5, receiveTimeout: Double = 0.5) {
		self.acceptTimeout = acceptTimeout
		self.receiveTimeout = receiveTimeout
	}

	public func bind(host: String, port: Int) throws -> Int {
		let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
		if socketDescriptor < 0 {
			throw SocketError.latest("socket")
		}
		var reuse: Int32 = 1
		setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

		var address = sockaddr_in()
		address.sin_family = sa_family_t(AF_INET)
		address.sin_port = in_port_t(UInt16(port).bigEndian)
		if inet_pton(AF_INET, host, &address.sin_addr) != 1 {
			Darwin.close(socketDescriptor)
			throw SocketError(call: "inet_pton", code: EINVAL)
		}
		let size = socklen_t(MemoryLayout<sockaddr_in>.size)
		let bound = withUnsafePointer(to: &address) { pointer in
			pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
				Darwin.bind(socketDescriptor, generic, size)
			}
		}
		if bound < 0 {
			let failure = SocketError.latest("bind")
			Darwin.close(socketDescriptor)
			throw failure
		}
		if Darwin.listen(socketDescriptor, 1) < 0 {
			let failure = SocketError.latest("listen")
			Darwin.close(socketDescriptor)
			throw failure
		}
		var timeout = timeval(
			tv_sec: Int(acceptTimeout),
			tv_usec: Int32((acceptTimeout - Double(Int(acceptTimeout))) * 1_000_000)
		)
		setsockopt(
			socketDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)
		)
		descriptor = socketDescriptor

		// The port actually bound is only knowable now, when the caller asked for port 0.
		var actual = sockaddr_in()
		var length = socklen_t(MemoryLayout<sockaddr_in>.size)
		let named = withUnsafeMutablePointer(to: &actual) { pointer in
			pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
				getsockname(socketDescriptor, generic, &length)
			}
		}
		return named == 0 ? Int(UInt16(bigEndian: actual.sin_port)) : port
	}

	public func accept() throws -> any Transport {
		let connection = Darwin.accept(descriptor, nil, nil)
		if connection < 0 {
			if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
				throw PollTimeout()
			}
			throw SocketError.latest("accept")
		}
		return SocketTransport(descriptor: connection, pollTimeout: receiveTimeout)
	}

	public func close() {
		guard descriptor >= 0 else { return }
		Darwin.close(descriptor)
		descriptor = -1
	}
}
