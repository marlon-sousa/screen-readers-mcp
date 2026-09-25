// ROLE: leaf adapter implementing the Transport seam over a real socket.
// USED BY: JsonLinesChannel, through the seam.
// BUILT BY: the two binder leaves, each handing over the descriptor its accept produced.
// The receive timeout keeps a blocked read from holding the session thread past its deadlines and a shutdown request.
// `SO_NOSIGPIPE` is required: on Darwin a send to a closed peer raises SIGPIPE, which kills the bridge before teardown restores the user's voice.
// Measured with VoiceOver on macOS 15: a skipped teardown left the capture voice selected, and VoiceOver later replaced the user's stored voice with the system default.

import Darwin
import Foundation

public final class SocketTransport: Transport {
	private var descriptor: Int32

	public init(descriptor: Int32, pollTimeout: Double = 0.5) {
		self.descriptor = descriptor
		var timeout = timeval(
			tv_sec: Int(pollTimeout),
			tv_usec: Int32((pollTimeout - Double(Int(pollTimeout))) * 1_000_000)
		)
		setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
		var noSigPipe: Int32 = 1
		setsockopt(
			descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
	}

	public func receive() throws -> Data {
		var buffer = [UInt8](repeating: 0, count: 8192)
		let count = recv(descriptor, &buffer, buffer.count, 0)
		if count < 0 {
			if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
				throw PollTimeout()
			}
			throw SocketError.latest("recv")
		}
		return Data(buffer[0..<count])
	}

	public func sendAll(_ data: Data) throws {
		try data.withUnsafeBytes { raw in
			var sent = 0
			while sent < raw.count {
				let written = send(descriptor, raw.baseAddress!.advanced(by: sent), raw.count - sent, 0)
				if written <= 0 {
					if errno == EINTR { continue }
					throw SocketError.latest("send")
				}
				sent += written
			}
		}
	}

	public func close() {
		guard descriptor >= 0 else { return }
		Darwin.close(descriptor)
		descriptor = -1
	}
}
