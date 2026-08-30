// ROLE: composition root -- the answer to "who connects what". It picks the
// adapters, stacks them, and hands the controllers their ports.
//
// AN AMENDMENT TO SPEC 0046's 13.4 LAYOUT, with its why: the layout names
// `Wiring` as the AdapterFactory's builder without giving it a file, and lane 1
// puts `wiring.py` beside the package rather than inside `adapters/`. It lands
// in the adapters module here for a reason that is Swift's and not a preference:
// SwiftPM cannot import an executable target into a test target, so a Wiring in
// `VoiceOverBridgeApp` would be unreachable from the integration scenarios --
// and a composition root nothing can exercise is the one file where a wiring
// mistake would survive every test. It imports the domain and the adapters,
// which is exactly what a composition root is allowed to do and nothing else is.
//
// USED BY: the integration scenarios today, and the container app from 13.10,
// when there is a dialog to start and stop the server from.
//
// IT MAKES NO DECISIONS OF ITS OWN. Every choice here is read from BridgeConfig
// or passed in; that is what keeps "which transport" a setting rather than
// something compiled in.

import Foundation
import ScreenReaderWire
import VoiceOverBridgeDomain

public enum Wiring {
	/// This bridge's own version. It travels in `hello` for the human reading a
	/// transcript and is NEVER compared with anything: what must match between
	/// two halves is the protocol version (spec 0012). 13.11 owns packaging and
	/// is where this stops being a literal.
	public static let bridgeVersion = "0.1.0-dev"

	/// The screen reader's version, which on macOS is the SYSTEM's.
	///
	/// VoiceOver has no version of its own to report: it ships with macOS and is
	/// updated with it, so the honest answer to "which VoiceOver?" is which macOS.
	/// Reported that way rather than as "unknown", because an agent comparing
	/// behaviour across machines needs the number that actually varies.
	public static func readerVersion() -> String {
		let version = ProcessInfo.processInfo.operatingSystemVersion
		return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
	}

	/// The directories the local endpoint's derivation needs, read from THIS
	/// process's environment. The one place in the bridge that reads them, so
	/// everything below is a pure function of values.
	public static func localSocketDirs() -> LocalSocketDirs {
		LocalSocketDirs(
			runtimeDir: ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"] ?? "",
			home: NSHomeDirectory()
		)
	}

	/// Where the capture voice's feed is read from, for THIS process.
	///
	/// The default is the extension's own container, derived by the same rule the
	/// extension derives it from -- see `ContainerFileSpeechSource`. The override
	/// is the same environment variable the extension reads (`VOCAPTURE_LOG`), so
	/// a developer can point both halves at one file in a temporary directory and
	/// exercise the feed with no reader at all: append a `synthesize` line and it
	/// arrives in the session's buffer.
	///
	/// The environment is read HERE and nowhere below, which is the same rule the
	/// endpoint's derivation follows: everything under this line is a pure
	/// function of values.
	public static func capturePath() -> String {
		let override = ProcessInfo.processInfo.environment["VOCAPTURE_LOG"] ?? ""
		guard override.isEmpty else { return override }
		return ContainerFileSpeechSource.containerFilePath(home: NSHomeDirectory())
	}

	/// Where the bridge tells the capture voice what it is asking of it.
	///
	/// The default is the same file the extension reads, derived by the same rule
	/// -- see `MarkerFileSilenceControl.containerMarkerPath`. The override is the
	/// same variable the extension reads (`VOCAPTURE_MARKER`), for the reason
	/// `VOCAPTURE_LOG`'s exists: both halves can be pointed at one temporary
	/// directory and capture mode exercised with no reader at all.
	public static func markerPath() -> String {
		let override = ProcessInfo.processInfo.environment["VOCAPTURE_MARKER"] ?? ""
		guard override.isEmpty else { return override }
		return MarkerFileSilenceControl.containerMarkerPath(home: NSHomeDirectory())
	}

	/// The capture voice's lifecycle, over the three signals that answer for it.
	///
	/// ONE PER PROCESS, not one per session: it describes the MACHINE, so a
	/// session-scoped one would run `pluginkit` again for an answer that cannot
	/// have changed because a socket was accepted.
	public static func providerLifecycle(runner: (any ProcessRunner)? = nil) -> any ProviderLifecycle {
		let tools = runner ?? SubprocessRunner()
		return PluginKitProviderLifecycle(
			runner: tools,
			published: SystemPublishedVoices(),
			store: SpeakSelectionVoiceStore(runner: tools),
			extensionBundleID: captureExtensionBundleID,
			voiceIdentifierSuffix: captureVoiceIdentifierSuffix
		)
	}

	/// How this bridge runs an AppleScript: `/usr/bin/osascript`, through the
	/// process seam that 13.6 already built.
	///
	/// ONE PER PROCESS, like the lifecycle and for a simpler reason: it holds no
	/// state whatsoever, so a second one would differ from the first in nothing.
	public static func appleScriptRunner(runner: (any ProcessRunner)? = nil) -> any AppleScriptRunner {
		OSAScriptRunner(runner: runner ?? SubprocessRunner())
	}

	/// Which endpoint to accept on, per the configured connection mode.
	public static func listener(
		config: any BridgeConfig,
		dirs: LocalSocketDirs? = nil
	) -> any Listener {
		switch config.connectionMode {
		case .localEndpoint:
			return LocalSocketListener(
				name: config.endpointName,
				dirs: dirs ?? localSocketDirs(),
				binder: UnixSocketBinder()
			)
		case .loopbackTcp:
			return TCPListener(port: config.loopbackPort, binder: TCPBinder())
		}
	}

	/// One connection becomes one session: the transport is framed as JSON lines,
	/// and the controller is handed ports only.
	public static func session(
		over transport: any Transport,
		clock: any Clock,
		transcript: any Transcript,
		signals: any SessionSignals,
		config: SessionConfig,
		handlers: [String: any CommandHandler]
	) -> Session {
		Session(
			channel: JsonLinesChannel(transport: transport),
			transcript: transcript,
			clock: clock,
			config: config,
			handlers: handlers,
			signals: signals
		)
	}

	/// The whole bridge: a listener, and a factory that turns each accepted
	/// connection into a session with a transcript of its own.
	///
	/// A TRANSCRIPT PER SESSION, not per process: the file is the record of ONE
	/// run, and two runs sharing one would leave a tester unable to tell which
	/// half they were reading.
	public static func bridgeServer(
		config: any BridgeConfig,
		signals: any SessionSignals,
		eventBus: (any EventBus)? = nil,
		logDirectory: String? = nil,
		clock: any Clock = RealClock(),
		lifecycle: (any ProviderLifecycle)? = nil,
		scripts: (any AppleScriptRunner)? = nil
	) -> BridgeServer {
		let handlers = Registry.build(
			factory: VoiceOverAdapterFactory(
				capturePath: capturePath(),
				markerPath: markerPath(),
				lifecycle: lifecycle ?? providerLifecycle(),
				scripts: scripts ?? appleScriptRunner()
			),
			readerVersion: readerVersion(),
			bridgeVersion: bridgeVersion
		)
		// ONE SOURCE FOR THE MACHINE'S ANSWER ABOUT ITS HUMAN. `attended` and the
		// silence cap's `enabled` are the same fact (protocol.md §6.2 keeps them
		// separable for readers whose cap can be switched off on its own; this one
		// has no such setting yet), so they are derived here, once, rather than in
		// two places that agree today.
		let sessionConfig = SessionConfig(
			readerVersion: readerVersion(),
			attended: config.attended,
			silenceCap: SilenceCapPolicy(enabled: config.attended)
		)
		let logs = logDirectory ?? FileTranscript.defaultLogDirectory(home: NSHomeDirectory())
		return BridgeServer(
			listener: listener(config: config),
			sessionFactory: { transport in
				session(
					over: transport,
					clock: clock,
					transcript: FileTranscript.session(in: logs),
					signals: signals,
					config: sessionConfig,
					handlers: handlers
				)
			},
			eventBus: eventBus
		)
	}
}
