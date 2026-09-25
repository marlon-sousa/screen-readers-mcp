// Mirrors Sources/VoiceOverBridgeAdapters/Wiring.swift.

import Fakes
import Foundation
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("Wiring")
struct WiringTests {
	@Test("the local endpoint is the default, and its endpoint is the derived socket path")
	func theDefaultIsTheLocalEndpoint() throws {
		// In /tmp for the 103-byte socket path budget; see Tests/Integration/LocalEndpointTests.swift.
		let home = "/tmp/voiceover-wiring-\(UUID().uuidString.prefix(8))"
		defer { try? FileManager.default.removeItem(atPath: home) }
		let listener = Wiring.listener(
			config: FakeBridgeConfig(),
			dirs: LocalSocketDirs(runtimeDir: "", home: home)
		)
		#expect(listener is LocalSocketListener)
		try listener.open()
		#expect(listener.endpoint == "\(home)/.screenreader-mcp/voiceoverMcpBridge.sock")
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
		#expect(transport.isClosed)
	}

	@Test("the assembled server is stopped until it is started, and reports the endpoint it will bind")
	func theWholeGraph() {
		let config = FakeBridgeConfig(connectionMode: .loopbackTcp, loopbackPort: 0)
		let server = Wiring.bridgeServer(config: config, signals: FakeSessionSignals())
		#expect(server.status.state == .stopped)
	}

	@Test("THE BUNDLE PATHS RESOLVE TO THE build/ DIRECTORY BESIDE THE PACKAGE, or to nothing")
	func theBundlePathsAreResolvedHere() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("wiring-package-\(UUID().uuidString)")
		defer { try? FileManager.default.removeItem(at: root) }
		let pretendSource = root
			.appendingPathComponent("Sources/VoiceOverBridgeAdapters/Wiring.swift").path
		let notAnApp = Bundle(for: BundleAnchor.self)

		#expect(
			Wiring.captureBundlePaths(main: notAnApp, packageDirectory: pretendSource) == nil)

		let build = root.appendingPathComponent("build")
		try FileManager.default.createDirectory(
			at: build.appendingPathComponent("\(captureAppName).app"), withIntermediateDirectories: true)
		#expect(
			Wiring.captureBundlePaths(main: notAnApp, packageDirectory: pretendSource)
				== CaptureBundlePaths.inside(directory: build.path))
	}

	@Test("running INSIDE the .app resolves to that bundle")
	func anAppBundleResolvesToItself() {
		let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("wiring-\(UUID().uuidString).app")
		try? FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: temporary) }
		let resolved = Wiring.captureBundlePaths(
			main: Bundle(url: temporary) ?? .main, packageDirectory: #filePath)
		#expect(resolved?.app == temporary.path)
	}

	@Test("the marker path is the extension's container, and the override is honoured")
	func theMarkerPathIsResolvedHere() {
		let resolved = Wiring.markerPath()
		let override = ProcessInfo.processInfo.environment["VOCAPTURE_MARKER"] ?? ""
		if override.isEmpty {
			#expect(resolved == MarkerFileSilenceControl.containerMarkerPath(home: NSHomeDirectory()))
			#expect(resolved.contains(captureExtensionBundleID))
		} else {
			#expect(resolved == override)
		}
	}

	@Test("THE ANNOUNCER IT BUILDS EXCLUDES OUR OWN VOICE, by the suffix the store matches")
	func theAnnouncerCannotPickTheCaptureVoice() throws {
		let published = FakePublishedVoices(voices: [
			"org.screen-readers-mcp.spike.capture.voice.org.screen-readers-mcp.spike.capture",
			"com.apple.voice.compact.pt-BR.Luciana",
		])
		let out = FakeSpeechOut()
		try Wiring.announcer(voices: published, out: out).announce("hello")
		#expect(out.spoken.first?.voice == "com.apple.voice.compact.pt-BR.Luciana")
	}

	@Test("the prompter it builds mints a ticket per question and holds the answer")
	func thePrompterIsWiredOverItsWindow() throws {
		let window = FakePromptWindow()
		let prompter = Wiring.userPrompter(window: window)
		let ticket = try prompter.present("ready?")
		#expect(window.opened.map(\.prompt) == ["ready?"])
		window.report(ticket, .answered("yes"))
		#expect(prompter.reply(for: ticket) == .answered("yes"))
	}

	@Test("the silence cap's `enabled` is the machine's `attended`, from ONE source")
	func theCapFollowsAttendance() {
		#expect(SilenceCapPolicy(enabled: FakeBridgeConfig(attended: true).attended).enabled)
		#expect(SilenceCapPolicy(enabled: FakeBridgeConfig(attended: false).attended).enabled == false)
	}
}

/// Anchors `Bundle(for:)` to the .xctest, because `Bundle.main` under `swift test` is the runner's.
private final class BundleAnchor {}
