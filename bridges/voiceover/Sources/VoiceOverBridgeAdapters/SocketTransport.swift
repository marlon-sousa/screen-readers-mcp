// ROLE: LEAF adapter -- IMPLEMENTS the Transport seam over a real socket, and
// nothing else.
//
// USED BY: JsonLinesChannel, through the seam, never directly. BUILT BY: the two
// binder leaves, each of which hands over the descriptor its accept produced.
//
// NO TEST FILE, and the reason is visible in the code: the only "logic" is
// translating a receive timeout into `PollTimeout` and a zero-length read into
// the empty Data that means end of stream. Both are the seam's contract stated
// once. Everything that decides anything is in JsonLinesChannel above it,
// exercised against a fake transport.
//
// THE RECEIVE TIMEOUT IS WHAT MAKES THE SESSION LOOP WORK AT ALL. Without it a
// blocked read would hold the session thread past its own watchdog deadlines and
// past any request to shut down, and the alternative -- a self-pipe to interrupt
// it -- is a state machine where a socket option will do.

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
