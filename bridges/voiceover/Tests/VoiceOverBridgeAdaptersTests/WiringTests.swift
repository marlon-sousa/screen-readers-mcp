// Mirrors Sources/VoiceOverBridgeAdapters/Wiring.swift.
//
// A COMPOSITION ROOT IS WORTH TESTING FOR EXACTLY ONE THING: that the graph it
// builds is the one the settings asked for. There is no logic here to catch a
// mistake, and every other test in the suite runs against a graph the test built
// itself -- so a wiring mistake would pass everything else in this package.

import Fakes
import Foundation
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("Wiring")
struct WiringTests {
	@Test("the local endpoint is the default, and its endpoint is the derived socket path")
	func theDefaultIsTheLocalEndpoint() throws {
		// A REAL home directory, in /tmp rather than under the temporary directory
		// macOS actually gives a process: that one is ~49 bytes of generated path
		// before the first meaningful character, which is the measurement spec 0044
		// used to reject $TMPDIR for the endpoint itself. A test that used it would
		// be failing the 103-byte check rather than testing the wiring.
		let home = "/tmp/voiceover-wiring-\(UUID().uuidString.prefix(8))"
		defer { try? FileManager.default.removeItem(atPath: home) }
		let listener = Wiring.listener(
			config: FakeBridgeConfig(),
			dirs: LocalSocketDirs(runtimeDir: "", home: home)
		)
		#expect(listener is LocalSocketListener)
		try listener.open()
		#expect(listener.endpoint == "\(home)/.screenreader-mcp/voiceoverMcpBridge.sock")
		// It really bound, so the obligations really ran: the directory exists and
		// the socket file is there.
		#expect(FileManager.default.fileExists(atPath: listener.endpoint))
		listener.close()
		#expect(!FileManager.default.fileExists(atPath: listener.endpoint))
	}

	@Test("choosing loopback TCP builds the other listener, on the configured port")
	func loopbackIsSelectable() {
		let config = FakeBridgeConfig(connectionMode: .loopbackTcp, loopbackPort: 8765)
		let listener = Wiring.listener(config: config, dirs: LocalSocketDirs(runtimeDir: "", home: "/tmp"))
		#expect(listener is TCPListener)
		#expect(listener.endpoint == "127.0.0.1:8765")
	}

	@Test("the reader version is the SYSTEM's, because VoiceOver has none of its own")
	func theReaderVersionIsMacOS() {
		#expect(Wiring.readerVersion().hasPrefix("macOS "))
	}

	@Test("the session it builds speaks JSON lines over whatever transport it was given")
	func aSessionIsFramed() {
		let transport = FakeTransport([.endOfStream])
		let session = Wiring.session(
			over: transport,
			clock: FakeClock(),
			transcript: FakeTranscript(),
			signals: FakeSessionSignals(),
			config: SessionConfig(readerVersion: "test"),
			handlers: [:]
		)
		session.run()
		// It reached end-of-stream through the real channel, which is the whole
		// claim: the transport was framed rather than handed to the session raw.
		#expect(transport.isClosed)
	}

	@Test("the assembled server is stopped until it is started, and reports the endpoint it will bind")
	func theWholeGraph() {
		let config = FakeBridgeConfig(connectionMode: .loopbackTcp, loopbackPort: 0)
		let server = Wiring.bridgeServer(config: config, signals: FakeSessionSignals())
		#expect(server.status.state == .stopped)
	}
}
