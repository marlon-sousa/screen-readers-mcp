// Mirrors Sources/VoiceOverBridgeAdapters/BridgeServer.swift.
//
// The accept loop runs on its own thread, so every assertion here waits for a
// condition rather than sleeping for a guess: a test that slept would be slow
// when it passed and flaky when it failed.

import Fakes
import Foundation
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("BridgeServer")
struct BridgeServerTests {
	/// Build a server whose sessions do nothing but record that they ran and end
	/// at once -- the accept loop is what is under test, not the session.
	private func makeServer(
		listener: FakeListener,
		bus: FakeEventBus = FakeEventBus(),
		onSession: (() -> Void)? = nil
	) -> (BridgeServer, FakeEventBus) {
		let server = BridgeServer(
			listener: listener,
			sessionFactory: { transport in
				onSession?()
				return Session(
					channel: JsonLinesChannel(transport: transport),
					transcript: FakeTranscript(),
					clock: FakeClock(),
					config: SessionConfig(readerVersion: "test"),
					handlers: [:],
					signals: FakeSessionSignals()
				)
			},
			eventBus: bus
		)
		return (server, bus)
	}

	private func waitUntil(_ condition: () -> Bool, seconds: Double = 5) -> Bool {
		let deadline = Date().addingTimeInterval(seconds)
		while Date() < deadline {
			if condition() { return true }
			usleep(2000)
		}
		return condition()
	}

	@Test("it starts stopped, reports listening once bound, and stopped again after stop")
	func theStatusLifecycle() throws {
		let listener = FakeListener(endpoint: "/tmp/x.sock")
		let (server, bus) = makeServer(listener: listener)
		#expect(server.status.state == .stopped)
		#expect(server.status.endpoint == nil)

		try server.start()
		#expect(server.status.state == .listening)
		#expect(server.status.endpoint == "/tmp/x.sock")

		server.stop()
		#expect(server.status.state == .stopped)
		#expect(server.status.endpoint == nil)
		#expect(listener.closeCount >= 1)
		#expect(bus.states.first == .listening)
		#expect(bus.states.last == .stopped)
	}

	@Test("binding happens on the CALLER's thread, so a bind failure is thrown to them")
	func aBindFailureReachesTheCaller() {
		final class RefusingListener: Listener {
			let endpoint = "refused"
			func open() throws { throw SocketError(call: "bind", code: 48) }
			func accept() throws -> any Transport { throw ListenerClosed() }
			func close() {}
		}
		let server = BridgeServer(
			listener: RefusingListener(),
			sessionFactory: { _ in fatalError("no session should be built") }
		)
		#expect(throws: SocketError.self) {
			try server.start()
		}
		// And it stays stopped rather than reporting a state it never reached.
		#expect(server.status.state == .stopped)
	}

	@Test("a connection becomes a session, and the server goes back to listening after it")
	func oneSessionAtATime() throws {
		let transport = FakeTransport([.endOfStream])
		let listener = FakeListener(script: [.connection(transport)])
		var built = 0
		let (server, bus) = makeServer(listener: listener, onSession: { built += 1 })
		try server.start()
		#expect(waitUntil { bus.states.contains(.sessionActive) })
		#expect(waitUntil { server.status.state == .listening })
		#expect(built == 1)
		server.stop()
		// listening, session-active, listening, stopped: the whole story, in order.
		#expect(bus.states == [.listening, .sessionActive, .listening, .stopped])
	}

	@Test("a session that blows up costs its own session and nothing else")
	func aSessionFaultDoesNotBreakTheServer() throws {
		// Lane 1's crashed-client lesson, carried over rather than re-learned. The
		// first connection's channel throws something the session never expected;
		// the server must still accept the second.
		final class ExplodingTransport: Transport {
			func receive() throws -> Data { throw SocketError(call: "recv", code: 54) }
			func sendAll(_ data: Data) throws {}
			func close() {}
		}
		let listener = FakeListener(script: [
			.connection(ExplodingTransport()),
			.idle,
			.connection(FakeTransport([.endOfStream])),
		])
		var built = 0
		let (server, _) = makeServer(listener: listener, onSession: { built += 1 })
		try server.start()
		#expect(waitUntil { built == 2 })
		server.stop()
	}

	@Test("a listener fault stops the server and leaves an honest status")
	func aListenerFaultStopsCleanly() throws {
		let listener = FakeListener(script: [.fault(SocketError(call: "accept", code: 9))])
		let (server, _) = makeServer(listener: listener)
		try server.start()
		#expect(waitUntil { server.status.state == .stopped })
		#expect(server.status.endpoint == nil)
		#expect(listener.closeCount >= 1)
	}

	@Test("start twice is a no-op, and stop twice is safe")
	func idempotence() throws {
		let listener = FakeListener()
		let (server, _) = makeServer(listener: listener)
		try server.start()
		try server.start()
		#expect(listener.openCount == 1)
		server.stop()
		server.stop()
		#expect(server.status.state == .stopped)
	}

	@Test("stop ends the live session rather than waiting for the peer to hang up")
	func stopTearsDownTheLiveSession() throws {
		// A transport that never says anything: without the teardown request the
		// session would poll until its own watchdog fired, and stop() would block
		// for its whole bounded wait.
		final class SilentTransport: Transport {
			func receive() throws -> Data { throw PollTimeout() }
			func sendAll(_ data: Data) throws {}
			func close() {}
		}
		let listener = FakeListener(script: [.connection(SilentTransport())])
		let (server, bus) = makeServer(listener: listener)
		try server.start()
		#expect(waitUntil { bus.states.contains(.sessionActive) })
		let started = Date()
		server.stop()
		#expect(Date().timeIntervalSince(started) < BridgeServer.stopTimeout)
		#expect(server.status.state == .stopped)
	}

	@Test("the live session's context is reachable while it runs, and nil when none is")
	func theLiveSessionIsReachable() throws {
		final class SilentTransport: Transport {
			func receive() throws -> Data { throw PollTimeout() }
			func sendAll(_ data: Data) throws {}
			func close() {}
		}
		let listener = FakeListener(script: [.connection(SilentTransport())])
		let (server, bus) = makeServer(listener: listener)
		#expect(server.currentSessionContext() == nil)
		try server.start()
		#expect(waitUntil { bus.states.contains(.sessionActive) })
		#expect(server.currentSessionContext() != nil)
		server.stop()
		#expect(server.currentSessionContext() == nil)
	}
}
