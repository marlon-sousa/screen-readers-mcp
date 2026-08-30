// Mirrors Sources/VoiceOverBridgeAdapters/TCPListener.swift.

import Fakes
import Testing

@testable import VoiceOverBridgeAdapters

@Suite("TCPListener")
struct TCPListenerTests {
	@Test("it binds loopback and nothing else -- the address is not a parameter")
	func loopbackOnly() throws {
		let binder = FakeLoopbackBinder()
		try TCPListener(port: 8765, binder: binder).open()
		#expect(binder.boundHosts == ["127.0.0.1"])
		#expect(binder.boundPorts == [8765])
	}

	@Test("the endpoint reports the port BOUND, not the port asked for")
	func theEndpointIsWhatWasBound() throws {
		// The case that makes this worth testing: a caller asks for 0 and the
		// kernel chooses. A status display showing "127.0.0.1:0" would be telling
		// a human to connect somewhere nothing is listening.
		let binder = FakeLoopbackBinder(answersWithPort: 51234)
		let listener = TCPListener(port: 0, binder: binder)
		try listener.open()
		#expect(listener.endpoint == "127.0.0.1:51234")
	}

	@Test("accepting after close is ListenerClosed, not a timeout")
	func acceptAfterClose() throws {
		let binder = FakeLoopbackBinder()
		let listener = TCPListener(port: 0, binder: binder)
		try listener.open()
		listener.close()
		#expect(throws: ListenerClosed.self) {
			try listener.accept()
		}
		#expect(binder.closeCount == 1)
	}

	@Test("an idle accept is a poll timeout")
	func idleAccept() throws {
		let listener = TCPListener(port: 0, binder: FakeLoopbackBinder())
		try listener.open()
		#expect(throws: PollTimeout.self) {
			try listener.accept()
		}
	}

	@Test("a bind failure reaches the caller")
	func bindFailure() {
		let binder = FakeLoopbackBinder()
		binder.bindFailure = SocketError(call: "bind", code: 48)
		#expect(throws: SocketError.self) {
			try TCPListener(port: 8765, binder: binder).open()
		}
	}
}
