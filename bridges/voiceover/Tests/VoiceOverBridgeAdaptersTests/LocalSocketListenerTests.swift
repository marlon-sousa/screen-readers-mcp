// Mirrors Sources/VoiceOverBridgeAdapters/LocalSocketListener.swift.
//
// EVERY TEST HERE IS ONE OF protocol.md §1's LISTENER OBLIGATIONS, which is why
// they are assertions about the ORDER of calls -- unusually for this repo. The
// effects live in a filesystem this test does not have; the sequence IS the
// contract, and getting it wrong fails in ways that look like something else
// entirely (a bridge that cannot restart, a socket nobody may connect to, a
// stale file that makes a dial fail on a machine where the bridge is running).

import Fakes
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("LocalSocketListener")
struct LocalSocketListenerTests {
	private let dirs = LocalSocketDirs(runtimeDir: "", home: "/Users/someone")
	private var socketPath: String { "/Users/someone/.screenreader-mcp/voiceoverMcpBridge.sock" }

	private func listener(
		name: String = "voiceoverMcpBridge",
		binder: FakeLocalSocketBinder
	) -> LocalSocketListener {
		LocalSocketListener(name: name, dirs: dirs, binder: binder)
	}

	@Test("open: the directory is made 0700, the stale socket unlinked, and THEN it binds")
	func theThreeObligationsInOrder() throws {
		let binder = FakeLocalSocketBinder()
		try listener(binder: binder).open()
		#expect(
			binder.calls == [
				.createDirectory(path: "/Users/someone/.screenreader-mcp", mode: 0o700),
				.removeFile(path: socketPath),
				.bind(path: socketPath),
			]
		)
	}

	@Test("0700 is the endpoint's whole security argument, so it is asserted as a number")
	func theDirectoryModeIsNotIncidental() throws {
		let binder = FakeLocalSocketBinder()
		try listener(binder: binder).open()
		guard case .createDirectory(_, let mode) = binder.calls[0] else {
			Issue.record("expected the directory to be created first")
			return
		}
		// Owner-only. It is where "reachable only by this user" comes from: a
		// socket in a world-writable directory is a bridge anybody on the machine
		// can drive.
		#expect(mode == 0o700)
	}

	@Test("the endpoint it reports is the derived path -- what the server dials")
	func theEndpointIsThePath() throws {
		let binder = FakeLocalSocketBinder()
		let listener = listener(binder: binder)
		try listener.open()
		#expect(listener.endpoint == socketPath)
	}

	@Test("an address written out as a path is bound verbatim, and its parent is left alone")
	func anExplicitPathIsNotAssumedToBeOurs() throws {
		let binder = FakeLocalSocketBinder()
		try listener(name: "/tmp/mine.sock", binder: binder).open()
		#expect(binder.calls == [.removeFile(path: "/tmp/mine.sock"), .bind(path: "/tmp/mine.sock")])
	}

	@Test("close unlinks the socket AFTER closing it, so nothing may dial a path that is gone")
	func closeUnlinksLast() throws {
		let binder = FakeLocalSocketBinder()
		let listener = listener(binder: binder)
		try listener.open()
		listener.close()
		#expect(binder.calls.suffix(2) == [.close, .removeFile(path: socketPath)])
	}

	@Test("a name too long to bind is refused before any of the obligations run")
	func anImpossibleNameFailsEarly() {
		let binder = FakeLocalSocketBinder()
		let tooLong = LocalSocketDirs(runtimeDir: "", home: "/Users/" + String(repeating: "x", count: 90))
		let listener = LocalSocketListener(name: "voiceoverMcpBridge", dirs: tooLong, binder: binder)
		#expect(throws: LocalSocketPathError.self) {
			try listener.open()
		}
		#expect(binder.calls.isEmpty)
	}

	@Test("a bind failure reaches the caller, on the caller's thread")
	func aBindFailureIsReported() {
		let binder = FakeLocalSocketBinder()
		binder.bindFailure = SocketError(call: "bind", code: 48)
		#expect(throws: SocketError.self) {
			try listener(binder: binder).open()
		}
	}

	@Test("accepting after close is ListenerClosed, not a timeout")
	func acceptAfterCloseIsClosed() throws {
		let binder = FakeLocalSocketBinder()
		let listener = listener(binder: binder)
		try listener.open()
		listener.close()
		#expect(throws: ListenerClosed.self) {
			try listener.accept()
		}
	}

	@Test("an idle accept is a poll timeout, so the accept loop can notice a stop")
	func idleAcceptIsATimeout() throws {
		let binder = FakeLocalSocketBinder()
		let listener = listener(binder: binder)
		try listener.open()
		#expect(throws: PollTimeout.self) {
			try listener.accept()
		}
	}

	@Test("a connection is handed through as the Transport a session runs over")
	func aConnectionIsHandedThrough() throws {
		let binder = FakeLocalSocketBinder()
		let connection = FakeTransport()
		binder.connections = [connection]
		let listener = listener(binder: binder)
		try listener.open()
		#expect(try listener.accept() as? FakeTransport === connection)
	}
}
