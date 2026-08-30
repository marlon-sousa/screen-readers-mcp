// ROLE: LEAF adapter -- IMPLEMENTS the LocalSocketBinder seam with the real
// socket and filesystem calls, and decides nothing.
//
// USED BY: LocalSocketListener, through the seam, never directly.
//
// NO TEST FILE. Which obligations must be honoured and in what order is
// protocol.md §1's rule, and it lives one layer up in the listener where it is
// tested against a fake of this seam. Everything here is the call the manual
// page describes.
//
// `listen(1)` IS ONE SESSION AT A TIME, matching the accept loop above: a second
// client waits in the backlog rather than being refused, which is what a server
// that reconnects expects to find.

import Darwin
import Foundation

public final class UnixSocketBinder: LocalSocketBinder {
	private var descriptor: Int32 = -1
	private let acceptTimeout: Double
	private let receiveTimeout: Double

	public init(acceptTimeout: Double = 0.5, receiveTimeout: Double = 0.5) {
		self.acceptTimeout = acceptTimeout
		self.receiveTimeout = receiveTimeout
	}

	public func createDirectory(at path: String, mode: Int) throws {
		try FileManager.default.createDirectory(
			atPath: path,
			withIntermediateDirectories: true,
			attributes: [.posixPermissions: mode]
		)
	}

	public func removeFile(at path: String) {
		unlink(path)
	}

	public func bind(to path: String) throws {
		let socketDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
		if socketDescriptor < 0 {
			throw SocketError.latest("socket")
		}
		var address = sockaddr_un()
		address.sun_family = sa_family_t(AF_UNIX)
		let bytes = Array(path.utf8)
		// The length was already checked where the endpoint was configured, which
		// is where a name can be reported back to whoever wrote it; this is the
		// belt to that braces, because writing past sun_path would be memory
		// damage rather than a bad configuration.
		guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
			Darwin.close(socketDescriptor)
			throw SocketError(call: "bind", code: ENAMETOOLONG)
		}
		withUnsafeMutablePointer(to: &address.sun_path) { field in
			field.withMemoryRebound(to: CChar.self, capacity: bytes.count + 1) { target in
				for (offset, byte) in bytes.enumerated() {
					target[offset] = CChar(bitPattern: byte)
				}
				target[bytes.count] = 0
			}
		}
		let size = socklen_t(MemoryLayout<sockaddr_un>.size)
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
