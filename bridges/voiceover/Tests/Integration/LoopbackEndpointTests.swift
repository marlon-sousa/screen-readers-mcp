// HEADLESS INTEGRATION -- the OTHER transport protocol.md §1 allows, over a real
// loopback socket.
//
// It is here rather than folded into the local-endpoint scenario because the two
// prove different things. That one proves the rendezvous: a path derived by the
// published rule, with the three obligations a socket file carries. This one
// proves the claim in the transport's own name -- that once a connection exists,
// the framing and every command are identical and the choice of transport is
// invisible after `hello`.
//
// It is also the only place TCPBinder runs at all: a leaf makes no decisions, so
// it has no unit test, and a leaf nothing exercises is a leaf that compiles.

import Darwin
import Fakes
import Foundation
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("the loopback endpoint")
struct LoopbackEndpointTests {
	@Test("a client dials 127.0.0.1 and gets the same session it would over a socket file")
	func aSessionOverLoopback() throws {
		// Port 0: the kernel picks a free one, which is also what proves the
		// endpoint reports the port BOUND rather than the port asked for.
		let listener = TCPListener(port: 0, binder: TCPBinder(acceptTimeout: 0.05, receiveTimeout: 0.05))
		let handlers = Registry.build(
			factory: VoiceOverAdapterFactory(), readerVersion: "macOS 15.0.0", bridgeVersion: "1.2.3"
		)
		let bridge = BridgeServer(
			listener: listener,
			sessionFactory: { transport in
				Wiring.session(
					over: transport,
					clock: RealClock(),
					transcript: FakeTranscript(),
					signals: FakeSessionSignals(),
					config: SessionConfig(readerVersion: "macOS 15.0.0"),
					handlers: handlers
				)
			}
		)
		try bridge.start()
		defer { bridge.stop() }

		let endpoint = try #require(bridge.status.endpoint)
		#expect(endpoint.hasPrefix("127.0.0.1:"))
		let port = try #require(Int(endpoint.split(separator: ":")[1]))
		#expect(port != 0)

		let descriptor = try dial(port: port)
		defer { Darwin.close(descriptor) }
		try write(descriptor, Request(id: 1, cmd: "hello", params: [
			"mode": .string("live"), "protocolVersion": .int(1),
		]))
		guard case .success(let value) = try read(descriptor).outcome() else {
			Issue.record("the handshake failed over loopback")
			return
		}
		#expect(try value.decoded(as: HelloResult.self).reader.name == "voiceover")

		try write(descriptor, Request(id: 2, cmd: "bye"))
		#expect(try read(descriptor).id == 2)
	}

	// -- a client made of nothing but the socket API --------------------------

	private func dial(port: Int, deadline: Double = 5) throws -> Int32 {
		let start = Date()
		while Date().timeIntervalSince(start) < deadline {
			let descriptor = socket(AF_INET, SOCK_STREAM, 0)
			var address = sockaddr_in()
			address.sin_family = sa_family_t(AF_INET)
			address.sin_port = in_port_t(UInt16(port).bigEndian)
			inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
			let connected = withUnsafePointer(to: &address) { pointer in
				pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
					Darwin.connect(descriptor, generic, socklen_t(MemoryLayout<sockaddr_in>.size))
				}
			}
			if connected == 0 {
				var timeout = timeval(tv_sec: 5, tv_usec: 0)
				setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
				return descriptor
			}
			Darwin.close(descriptor)
			usleep(5000)
		}
		throw SocketError.latest("connect")
	}

	private func write(_ descriptor: Int32, _ request: Request) throws {
		var data = try JSONEncoder().encode(request)
		data.append(0x0A)
		_ = data.withUnsafeBytes { raw in Darwin.send(descriptor, raw.baseAddress, raw.count, 0) }
	}

	private func read(_ descriptor: Int32) throws -> Response {
		var buffered = Data()
		while true {
			if let newline = buffered.firstIndex(of: 0x0A) {
				return try JSONDecoder().decode(Response.self, from: Data(buffered[..<newline]))
			}
			var buffer = [UInt8](repeating: 0, count: 4096)
			let count = recv(descriptor, &buffer, buffer.count, 0)
			if count <= 0 {
				throw ValidationError(path: "", reason: "the bridge sent nothing back")
			}
			buffered.append(contentsOf: buffer[0..<count])
		}
	}
}
