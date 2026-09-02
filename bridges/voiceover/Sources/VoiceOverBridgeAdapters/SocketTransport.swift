// ROLE: LEAF adapter -- IMPLEMENTS the Transport seam over a real socket, and
// nothing else.
//
// USED BY: JsonLinesChannel, through the seam, never directly. BUILT BY: the two
// binder leaves, each of which hands over the descriptor its accept produced.
//
// ALMOST NO TEST FILE, and the "almost" is the point. The only "logic" here is
// translating a receive timeout into `PollTimeout` and a zero-length read into
// the empty Data that means end of stream. Both are the seam's contract stated
// once, and everything that decides anything is in JsonLinesChannel above it,
// exercised against a fake transport. So this leaf followed the rule and had no
// test at all -- until 2026-09-02, when `SocketTransportTests.swift` was added
// for the ONE thing above it cannot assert: that the process is still running
// after a write to a peer that hung up. See the next paragraph and that file.
//
// THE RECEIVE TIMEOUT IS WHAT MAKES THE SESSION LOOP WORK AT ALL. Without it a
// blocked read would hold the session thread past its own watchdog deadlines and
// past any request to shut down, and the alternative -- a self-pipe to interrupt
// it -- is a state machine where a socket option will do.
//
// AND `SO_NOSIGPIPE` IS WHAT KEEPS THE BRIDGE ALIVE LONG ENOUGH TO TEAR DOWN.
// On Darwin a `send` to a peer that has already closed raises SIGPIPE, whose
// default disposition TERMINATES THE PROCESS -- so the write does not fail, the
// bridge simply ceases to exist, mid-statement, with no error anywhere. Every
// line of Session.endSession is then skipped: the silence marker is not
// released, `restoreVoice` never runs, and the socket file is left behind so the
// next dial answers `connection refused`.
//
// MEASURED 2026-09-02, twice, on the 13.20 live checklist. `connect_reader` with
// VoiceOver not running overran the server's 15 s hello budget; the server hung
// up mid-handshake; this `send` killed the bridge with signal 13 (exit 141).
// Because rung 4 had already pointed the reader at the capture voice and the
// teardown never ran, the selection was left dangling -- and when VoiceOver was
// next restarted it found that voice unpublished, fell back to the system
// default AND PERSISTED IT, destroying the stored record of the user's own
// voice. The damage outlived the crash, which is what makes this a socket option
// rather than a robustness nicety.
//
// WHY THE OPTION AND NOT `signal(SIGPIPE, SIG_IGN)` AT THE PROCESS ENTRY: this
// bridge is a library with two entry points -- `BridgeListener` and the shipped
// `.app` -- so a fix at either one is a fix at only one. The option travels with
// the descriptor that has the problem. It is also narrower: ignoring the signal
// process-wide would silence it for every other file descriptor too, including
// ones where a dead pipe means something else entirely.
//
// WHAT IT CHANGES: `send` returns -1 with `errno == EPIPE` instead of raising,
// so the existing `SocketError.latest("send")` below reports it as an ordinary
// channel failure, the session ends by its normal path, and hard invariant 3's
// two teardown steps run. A leaf still deciding nothing -- this is the same kind
// of thing as the receive timeout above: a socket option that makes the seam's
// contract achievable at all.

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
