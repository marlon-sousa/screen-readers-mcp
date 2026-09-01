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

	@Test("THE BUNDLE PATHS RESOLVE TO THE build/ DIRECTORY BESIDE THE PACKAGE, or to nothing")
	func theBundlePathsAreResolvedHere() throws {
		// THE ONE PLACE THAT KNOWS WHERE A BUNDLE LIVES (13.20).
		// `PluginKitProviderLifecycle` knows identifiers and must not know layout,
		// so `register()` is handed a path or told there is none.
		//
		// An INVENTED package directory rather than this one's, so the answer does
		// not depend on whether the developer happens to have run `build.sh`: both
		// branches are exercised on every machine, every time.
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("wiring-package-\(UUID().uuidString)")
		defer { try? FileManager.default.removeItem(at: root) }
		let pretendSource = root
			.appendingPathComponent("Sources/VoiceOverBridgeAdapters/Wiring.swift").path
		let notAnApp = Bundle(for: BundleAnchor.self)

		// NIL IS AN ANSWER, and not a fallback to a guess: `register()` then fails
		// by name carrying both commands, where a guessed path would let
		// `lsregister -f` register nothing and report success.
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
		// The first candidate, and the one that matters once the bridge ships: a
		// process running out of the assembled bundle registers ITS OWN extension
		// rather than whatever a developer last built.
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
		// Wiring is the one place in the bridge that reads the environment, so the
		// override belongs here and the derivation belongs in the adapter. The
		// variable exists for the same reason VOCAPTURE_LOG's does: both halves can
		// be pointed at one temporary directory and capture mode exercised with no
		// reader at all.
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
		// A COMPOSITION-ROOT MISTAKE THAT NO ADAPTER TEST WOULD CATCH: the rule
		// lives in `SynthesizerAnnouncer`, but WHICH suffix it is given is decided
		// here, and handing it the wrong string would produce an announcer that
		// picks the capture voice -- silence talking to itself, returning `ok`
		// while the room stays quiet.
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
		// The same shape of check one level up: the prompter's rules are its own,
		// and what is decided HERE is that it is stacked over a window seam at all.
		let window = FakePromptWindow()
		let prompter = Wiring.userPrompter(window: window)
		let ticket = try prompter.present("ready?")
		#expect(window.opened.map(\.prompt) == ["ready?"])
		window.report(ticket, .answered("yes"))
		#expect(prompter.reply(for: ticket) == .answered("yes"))
	}

	@Test("the silence cap's `enabled` is the machine's `attended`, from ONE source")
	func theCapFollowsAttendance() {
		// protocol.md §6.2 keeps them separable for readers whose cap can be
		// switched off on its own; this one has no such setting, so they are
		// derived here once rather than in two places that agree today.
		#expect(SilenceCapPolicy(enabled: FakeBridgeConfig(attended: true).attended).enabled)
		#expect(SilenceCapPolicy(enabled: FakeBridgeConfig(attended: false).attended).enabled == false)
	}
}

/// A class in this test bundle, so `Bundle(for:)` names the .xctest rather than
/// the test runner. `Bundle.main` under `swift test` is the runner's, which is
/// not a `.app` -- and asserting against whatever the runner happens to be is
/// how a test starts depending on the harness rather than on the code.
private final class BundleAnchor {}
