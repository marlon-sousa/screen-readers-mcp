// Mirrors Sources/VoiceOverBridgeAdapters/SocketTransport.swift.
// If SO_NOSIGPIPE regresses this does not fail as an assertion: SIGPIPE kills the test runner with signal 13 and no per-test report.

import Darwin
import Foundation
import Testing

@testable import VoiceOverBridgeAdapters

@Suite("the socket transport")
struct SocketTransportTests {
	private func connectedPair() -> (ours: Int32, theirs: Int32) {
		var descriptors: [Int32] = [0, 0]
		let made = socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors)
		#expect(made == 0, "socketpair failed with errno \(errno)")
		return (descriptors[0], descriptors[1])
	}

	@Test("writing to a peer that hung up FAILS, and does not kill the process")
	func sendToClosedPeerThrows() throws {
		let pair = connectedPair()
		let transport = SocketTransport(descriptor: pair.ours)
		defer { transport.close() }

		Darwin.close(pair.theirs)

		// The first write can succeed before the peer's RST arrives, so the loop, not one call, is the assertion.
		var failed = false
		for _ in 0..<8 {
			do {
				try transport.sendAll(Data("{\"id\":1}\n".utf8))
			} catch {
				failed = true
				break
			}
		}
		#expect(failed, "a write to a hung-up peer must fail rather than be swallowed")
	}

	@Test("an ordinary write to a live peer still succeeds")
	func sendToLivePeerSucceeds() throws {
		let pair = connectedPair()
		let transport = SocketTransport(descriptor: pair.ours)
		defer {
			transport.close()
			Darwin.close(pair.theirs)
		}

		try transport.sendAll(Data("hello\n".utf8))

		var buffer = [UInt8](repeating: 0, count: 32)
		let count = recv(pair.theirs, &buffer, buffer.count, 0)
		#expect(count == 6)
		#expect(String(decoding: buffer[0..<max(count, 0)], as: UTF8.self) == "hello\n")
	}
}
