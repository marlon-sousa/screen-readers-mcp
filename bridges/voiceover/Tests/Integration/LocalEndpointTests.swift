// HEADLESS INTEGRATION -- the bridge LISTENING, on a real endpoint, dialled by a
// real client socket. No VoiceOver, no MCP server, no second process.
//
// THIS IS THE ENTRY'S HEADLINE CLAIM, and it is the one thing no unit test in
// this package can make: 13.4 is the first point at which something outside this
// machine's Swift code can establish a session with this bridge. The listener's
// obligations are unit-tested against a fake binder because their ORDER is the
// contract; here the kernel is the judge instead -- the socket really appears at
// the derived path, a stale one really is replaced, and a restart really works.
//
// The path is derived by the same rule the Go server uses (protocol.md §1), from
// a home directory this test invents, so it exercises the derivation without
// touching the developer's own endpoint.

import Darwin
import Fakes
import Foundation
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("the local endpoint")
struct LocalEndpointTests {
	/// A client that dials a unix socket and speaks JSON lines, standing in for
	/// the Go server. Deliberately built from the raw socket API rather than from
	/// this package's own transport: a round trip proven with our own code on both
	/// ends would not prove the endpoint is dialable.
	private final class Client {
		private var descriptor: Int32 = -1
		private var buffered = Data()

		func connect(toPath path: String, deadline: Double = 5) throws {
			let start = Date()
			while Date().timeIntervalSince(start) < deadline {
				let socketDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
				var address = sockaddr_un()
				address.sun_family = sa_family_t(AF_UNIX)
				let bytes = Array(path.utf8)
				withUnsafeMutablePointer(to: &address.sun_path) { field in
					field.withMemoryRebound(to: CChar.self, capacity: bytes.count + 1) { target in
						for (offset, byte) in bytes.enumerated() { target[offset] = CChar(bitPattern: byte) }
						target[bytes.count] = 0
					}
				}
				let connected = withUnsafePointer(to: &address) { pointer in
					pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
						Darwin.connect(socketDescriptor, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
					}
				}
				if connected == 0 {
					descriptor = socketDescriptor
					var timeout = timeval(tv_sec: 5, tv_usec: 0)
					setsockopt(
						descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)
					)
					return
				}
				Darwin.close(socketDescriptor)
				usleep(5000)
			}
			throw SocketError.latest("connect")
		}

		func send(id: Int, cmd: String, params: [String: JSONValue] = [:]) throws {
			var data = try JSONEncoder().encode(Request(id: id, cmd: cmd, params: params))
			data.append(0x0A)
			_ = data.withUnsafeBytes { raw in
				Darwin.send(descriptor, raw.baseAddress, raw.count, 0)
			}
		}

		func reply() throws -> Response {
			while true {
				if let newline = buffered.firstIndex(of: 0x0A) {
					let line = Data(buffered[buffered.startIndex..<newline])
					buffered = Data(buffered[buffered.index(after: newline)...])
					return try JSONDecoder().decode(Response.self, from: line)
				}
				var buffer = [UInt8](repeating: 0, count: 4096)
				let count = recv(descriptor, &buffer, buffer.count, 0)
				if count <= 0 {
					throw ValidationError(path: "", reason: "the bridge sent nothing back")
				}
				buffered.append(contentsOf: buffer[0..<count])
			}
		}

		func close() {
			if descriptor >= 0 { Darwin.close(descriptor) }
			descriptor = -1
		}
	}

	/// A home directory of this test's own, in /tmp because the temporary
	/// directory macOS hands a process is ~49 bytes before the first meaningful
	/// character -- half the 103-byte budget, spent on nothing.
	private func temporaryHome() -> String {
		"/tmp/voiceover-endpoint-\(UUID().uuidString.prefix(8))"
	}

	private func server(home: String, attended: Bool = true) -> (BridgeServer, String) {
		let dirs = LocalSocketDirs(runtimeDir: "", home: home)
		let listener = LocalSocketListener(
			name: defaultEndpointName,
			dirs: dirs,
			binder: UnixSocketBinder(acceptTimeout: 0.05, receiveTimeout: 0.05)
		)
		let handlers = Registry.build(
			factory: VoiceOverAdapterFactory(capturePath: unusedCapturePath()), readerVersion: "macOS 15.0.0", bridgeVersion: "1.2.3"
		)
		let server = BridgeServer(
			listener: listener,
			sessionFactory: { transport in
				Wiring.session(
					over: transport,
					clock: RealClock(),
					transcript: FakeTranscript(),
					signals: FakeSessionSignals(),
					config: SessionConfig(readerVersion: "macOS 15.0.0", attended: attended),
					handlers: handlers
				)
			}
		)
		return (server, "\(home)/.screenreader-mcp/\(defaultEndpointName).sock")
	}

	@Test("a client dials the derived path, says hello, echoes, and says goodbye")
	func awholeSessionOverARealSocket() throws {
		let home = temporaryHome()
		defer { try? FileManager.default.removeItem(atPath: home) }
		let (bridge, path) = server(home: home)
		try bridge.start()
		defer { bridge.stop() }

		#expect(bridge.status.endpoint == path)
		#expect(FileManager.default.fileExists(atPath: path))

		let client = Client()
		try client.connect(toPath: path)
		defer { client.close() }

		try client.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		guard case .success(let value) = try client.reply().outcome() else {
			Issue.record("the handshake failed over a real socket")
			return
		}
		#expect(try value.decoded(as: HelloResult.self).reader.name == "voiceover")

		try client.send(id: 2, cmd: "echo", params: ["payload": .string("over a real socket")])
		guard case .success(let echoed) = try client.reply().outcome() else {
			Issue.record("echo failed over a real socket")
			return
		}
		#expect(try echoed.decoded(as: EchoResult.self).payload == .string("over a real socket"))

		try client.send(id: 3, cmd: "bye")
		#expect(try client.reply().id == 3)
	}

	@Test("the directory is created owner-only, which is where the endpoint's privacy comes from")
	func theDirectoryIsOwnerOnly() throws {
		let home = temporaryHome()
		defer { try? FileManager.default.removeItem(atPath: home) }
		let (bridge, _) = server(home: home)
		try bridge.start()
		defer { bridge.stop() }

		let attributes = try FileManager.default.attributesOfItem(
			atPath: "\(home)/.screenreader-mcp"
		)
		let permissions = attributes[.posixPermissions] as? NSNumber
		#expect(permissions?.int16Value == 0o700)
	}

	@Test("a socket file left behind by a crash does not stop the bridge starting")
	func aStaleSocketIsReplaced() throws {
		// Without the unlink-before-bind obligation this is not an edge case: it is
		// every restart after a crash, and the failure says "address already in
		// use" about a socket nothing is listening on.
		let home = temporaryHome()
		defer { try? FileManager.default.removeItem(atPath: home) }
		let (bridge, path) = server(home: home)
		try FileManager.default.createDirectory(
			atPath: "\(home)/.screenreader-mcp", withIntermediateDirectories: true
		)
		FileManager.default.createFile(atPath: path, contents: Data("stale".utf8))

		try bridge.start()
		defer { bridge.stop() }
		let client = Client()
		try client.connect(toPath: path)
		defer { client.close() }
		try client.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		#expect(try client.reply().id == 1)
	}

	@Test("stopping unlinks the socket, so a dial afterwards fails rather than hanging")
	func stoppingRemovesTheSocket() throws {
		let home = temporaryHome()
		defer { try? FileManager.default.removeItem(atPath: home) }
		let (bridge, path) = server(home: home)
		try bridge.start()
		#expect(FileManager.default.fileExists(atPath: path))
		bridge.stop()
		#expect(!FileManager.default.fileExists(atPath: path))
	}

	@Test("the bridge accepts a SECOND session after the first has ended")
	func itKeepsAccepting() throws {
		// One session at a time, but not one session ever: an agent that
		// disconnects and reconnects is the ordinary case, and lane 1's accept loop
		// exists precisely so a finished session returns the server to listening.
		let home = temporaryHome()
		defer { try? FileManager.default.removeItem(atPath: home) }
		let (bridge, path) = server(home: home)
		try bridge.start()
		defer { bridge.stop() }

		for round in 1...2 {
			let client = Client()
			try client.connect(toPath: path)
			try client.send(
				id: round, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)]
			)
			#expect(try client.reply().id == round)
			try client.send(id: round + 10, cmd: "bye")
			#expect(try client.reply().id == round + 10)
			client.close()
			// The server must be back to listening before the next dial, which is
			// the state transition BridgeServer's own test asserts in isolation.
			let deadline = Date().addingTimeInterval(5)
			while bridge.status.state != .listening, Date() < deadline {
				usleep(2000)
			}
			#expect(bridge.status.state == .listening)
		}
	}
}
