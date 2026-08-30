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
		clock: any Clock = RealClock()
	) -> BridgeServer {
		let handlers = Registry.build(
			factory: VoiceOverAdapterFactory(capturePath: capturePath()),
			readerVersion: readerVersion(),
			bridgeVersion: bridgeVersion
		)
		let sessionConfig = SessionConfig(readerVersion: readerVersion(), attended: config.attended)
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
