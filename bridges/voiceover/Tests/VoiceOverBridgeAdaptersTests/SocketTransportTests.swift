// Mirrors Sources/VoiceOverBridgeAdapters/SocketTransport.swift.
//
// THIS FILE IS A DELIBERATE EXCEPTION TO "LEAF ADAPTERS GET NO TEST FILE", and
// the exception is worth more than the rule here. That rule's reason is that a
// leaf makes no decisions, so there is nothing `send()` does not already
// guarantee -- and it is right about `send()`. It is wrong about the SOCKET
// OPTION, because the thing being asserted is not what the call returns but that
// THE PROCESS IS STILL RUNNING AFTERWARDS. Nothing above this layer can assert
// that: a fake transport cannot raise SIGPIPE, and a process that has been
// terminated by a signal reports no failure anywhere.
//
// WHAT IT GUARDS. On Darwin a `send` to a peer that has already closed raises
// SIGPIPE, whose default disposition terminates the process. Without
// `SO_NOSIGPIPE` the bridge does not fail the write -- it ceases to exist,
// skipping every line of `Session.endSession`: the silence marker is not
// released, the user's own voice is never restored, and the endpoint file is
// left behind so the next dial answers `connection refused`.
//
// MEASURED 2026-09-02, twice, on the 13.20 live checklist. `connect_reader` with
// VoiceOver not running overran the server's 15 s hello budget, the server hung
// up mid-handshake, and the bridge died with signal 13 (exit 141). Rung 4 had
// already pointed the reader at the capture voice, so the dangling selection
// outlived the crash: the next VoiceOver restart found that voice unpublished,
// fell back to the system default AND PERSISTED IT, destroying the stored record
// of the maintainer's own voice. The damage outlasted the process, which is why
// this is a regression test and not a note in a header.
//
// HOW IT FAILS IF IT REGRESSES, because this is unusual and a future reader
// deserves the warning: it does not fail as an assertion. The SIGPIPE terminates
// the TEST RUNNER, so the whole suite dies at once with signal 13 and no
// per-test report. That is loud, unmistakable, and exactly the hazard -- a
// quieter signal would mean the test was not reproducing the bug.
//
// A SOCKETPAIR RATHER THAN A LISTENER, so there is no accept, no path, no
// timing and no cleanup: two connected descriptors, one closed on purpose.

import Darwin
import Foundation
import Testing

@testable import VoiceOverBridgeAdapters

@Suite("the socket transport")
struct SocketTransportTests {
	/// Two connected descriptors. The transport takes the first; the test closes
	/// the second to stand in for a server that hung up.
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

		// The first write can legitimately succeed: it lands in a socket buffer
		// whose peer is gone but whose RST has not arrived yet. The second is the
		// one that meets EPIPE -- so the loop is the assertion, not a single call.
		// Reaching the end of this function AT ALL is the property under test.
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

		// The control for the test above: SO_NOSIGPIPE must not have turned every
		// write into a failure. Without this, a transport that always threw would
		// pass the first test for entirely the wrong reason.
		try transport.sendAll(Data("hello\n".utf8))

		var buffer = [UInt8](repeating: 0, count: 32)
		let count = recv(pair.theirs, &buffer, buffer.count, 0)
		#expect(count == 6)
		#expect(String(decoding: buffer[0..<max(count, 0)], as: UTF8.self) == "hello\n")
	}
}
