// ROLE: composition root: picks the adapters, stacks them, and hands the controllers their ports.
// It lives in the adapters module because SwiftPM cannot import an executable target into a test
// target.
// USED BY: the integration scenarios and the headless launcher.

import Foundation
import ScreenReaderWire
import VoiceOverBridgeDomain

public enum Wiring {
	/// This bridge's own version, reported in `hello` and never compared with anything.
	public static let bridgeVersion = voiceOverBridgeVersion

	/// The reader's version, which on macOS is the system's: VoiceOver ships and updates with macOS.
	public static func readerVersion() -> String {
		let version = ProcessInfo.processInfo.operatingSystemVersion
		return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
	}

	/// The one place the bridge reads these directories from the environment.
	public static func localSocketDirs() -> LocalSocketDirs {
		LocalSocketDirs(
			runtimeDir: ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"] ?? "",
			home: NSHomeDirectory()
		)
	}

	/// Where the capture feed is read from; `VOCAPTURE_LOG` overrides it, as it does for the extension,
	/// so both halves can share one file with no reader at all.
	public static func capturePath() -> String {
		let override = ProcessInfo.processInfo.environment["VOCAPTURE_LOG"] ?? ""
		guard override.isEmpty else { return override }
		return ContainerFileSpeechSource.containerFilePath(home: NSHomeDirectory())
	}

	/// Where the bridge tells the capture voice what it asks of it; `VOCAPTURE_MARKER` overrides it, as
	/// it does for the extension.
	public static func markerPath() -> String {
		let override = ProcessInfo.processInfo.environment["VOCAPTURE_MARKER"] ?? ""
		guard override.isEmpty else { return override }
		return MarkerFileSilenceControl.containerMarkerPath(home: NSHomeDirectory())
	}

	/// Where this process's own `.app` bundle is, if it can be found at all.
	/// Tries `Bundle.main`, then `build/` beside the package. Nil makes `register()` fail by name, where
	/// a guessed path would let `lsregister -f` register nothing and report success.
	public static func captureBundlePaths(
		main: Bundle = .main,
		fileManager: FileManager = .default,
		packageDirectory: String = #filePath
	) -> CaptureBundlePaths? {
		if main.bundleURL.pathExtension == "app" {
			return CaptureBundlePaths.inside(app: main.bundleURL.path)
		}
		// Sources/VoiceOverBridgeAdapters/Wiring.swift -> the package root.
		let package = URL(fileURLWithPath: packageDirectory)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		let candidate = CaptureBundlePaths.inside(
			directory: package.appendingPathComponent("build").path)
		return fileManager.fileExists(atPath: candidate.app) ? candidate : nil
	}

	/// The capture voice's lifecycle, over the three signals that answer for it.
	/// One per process: it describes the machine, which a new session cannot change.
	public static func providerLifecycle(
		runner: (any ProcessRunner)? = nil,
		paths: CaptureBundlePaths? = nil,
		clock: any Clock = RealClock()
	) -> any ProviderLifecycle {
		let tools = runner ?? SubprocessRunner()
		return PluginKitProviderLifecycle(
			runner: tools,
			published: SystemPublishedVoices(),
			store: SpeakSelectionVoiceStore(runner: tools),
			extensionBundleID: captureExtensionBundleID,
			voiceIdentifierSuffix: captureVoiceIdentifierSuffix,
			bundlePaths: paths ?? captureBundlePaths(),
			clock: clock
		)
	}

	/// What this process is allowed to do to the machine, and the one object that
	/// can ask for more.
	/// Constructing it asks for nothing; only the two command handlers, through `AccessibilityGrant`,
	/// may call `request`.
	public static func permissionBroker() -> any PermissionBroker {
		TCCPermissionBroker()
	}

	/// How a synthesized keystroke leaves this process: one Core Graphics event
	/// per chunk of text, or per key of a chord.
	/// Built only here: a test that built it would type into whatever window the developer has open.
	public static func eventPoster() -> any EventPoster {
		CGEventPoster()
	}

	/// Which physical key produces a character on the layout that is active now.
	/// One per process: the reverse map costs 256 UCKeyTranslate calls to build, and it re-reads the
	/// input source on every lookup, so a layout switch mid-session is still followed.
	public static func keyboardLayout() -> any KeyboardLayout {
		CurrentKeyboardLayout()
	}

	/// How this bridge reads another application's accessibility tree.
	public static func accessibilityTree() -> any AccessibilityTree {
		AXAccessibilityTree()
	}

	/// Who is in front, over NSWorkspace; it costs no permission.
	public static func frontmostApplication() -> any FrontmostApplication {
		WorkspaceFrontmostApplication()
	}

	/// Whether this process may read an accessibility tree; the same class as `permissionBroker()`, and
	/// `isTrusted` shows no dialog.
	public static func accessibilityTrust() -> any AccessibilityTrust {
		TCCPermissionBroker()
	}

	/// How this bridge speaks to the human at the reader.
	/// One per process. It must never pick the capture voice, which renders silence in a silent session.
	public static func announcer(
		voices: (any PublishedVoices)? = nil,
		out: (any SpeechOut)? = nil
	) -> any Announcer {
		SynthesizerAnnouncer(
			voices: voices ?? SystemPublishedVoices(),
			out: out ?? AVSpeechOut(),
			excludingSuffix: captureVoiceIdentifierSuffix,
			preferredLanguage: preferredLanguage()
		)
	}

	/// The language the human at this machine reads in, as the system spells it.
	public static func preferredLanguage() -> String {
		Locale.preferredLanguages.first ?? "en-US"
	}

	/// How this bridge asks the human a question; one per process, so one holder of the tickets.
	public static func userPrompter(window: (any PromptWindow)? = nil) -> any UserPrompter {
		AppKitUserPrompter(window: window ?? AppKitPromptWindow())
	}

	/// What the person at this machine has bound their VoiceOver modifier to.
	/// Reads through `VoiceOverPreferencesFile`, so every reader of VoiceOver's preferences agrees on
	/// where they live.
	public static func readerModifierSetting(
		reader: (any PlistReader)? = nil
	) -> any ReaderModifierSetting {
		VoiceOverPrefsModifierSetting(reader: reader ?? FilePlistReader(), home: NSHomeDirectory())
	}

	/// How the reader is taken away and brought back; it can leave a blind person with no screen
	/// reader, so it is built only here.
	public static func readerRestart(
		tools: (any ProcessRunner)? = nil,
		applications: (any RunningApplications)? = nil,
		clock: any Clock = RealClock()
	) -> any ReaderRestart {
		VoiceOverRestart(
			tools: tools ?? SubprocessRunner(),
			applications: applications ?? WorkspaceRunningApplications(),
			clock: clock)
	}

	/// The record of what sessions on this machine changed and put back.
	/// One file for the whole machine, appended to by every session: a crashed session cannot be
	/// relied on to name its own file.
	public static func changeJournal(home: String = NSHomeDirectory()) -> any ChangeJournal {
		let path = FileChangeJournal.defaultPath(home: home)
		try? FileManager.default.createDirectory(
			atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path,
			withIntermediateDirectories: true)
		// Appending: truncating would wipe every earlier session's unresolved changes.
		return FileChangeJournal(writer: AppendingTextFileWriter(path: path))
	}

	/// The persisted settings; one per process, and it caches nothing.
	public static func bridgeConfig(defaults: (any Defaults)? = nil) -> any BridgeConfig {
		UserDefaultsBridgeConfig(defaults: defaults ?? UserDefaultsStore())
	}

	/// The audible cues, and the preference that silences them.
	/// Takes the config so the switch is read on every cue, and turning cues off applies at once.
	public static func sessionSignals(
		config: any BridgeConfig,
		announcer speaker: (any Announcer)? = nil,
		tones: (any Tones)? = nil
	) -> any SessionSignals {
		AudibleSessionSignals(
			tones: tones ?? CoreAudioTones(), announcer: speaker ?? announcer(), config: config)
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

	/// One connection becomes one session, framed as JSON lines.
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
	/// A transcript per session, so a file is the record of one run.
	public static func bridgeServer(
		config: any BridgeConfig,
		signals: any SessionSignals,
		eventBus: (any EventBus)? = nil,
		logDirectory: String? = nil,
		clock: any Clock = RealClock(),
		lifecycle: (any ProviderLifecycle)? = nil,
		tools: (any ProcessRunner)? = nil,
		permissions: (any PermissionBroker)? = nil,
		poster: (any EventPoster)? = nil,
		layout: (any KeyboardLayout)? = nil,
		readerModifier: (any ReaderModifierSetting)? = nil,
		readerRestart: (any ReaderRestart)? = nil,
		changeJournal: (any ChangeJournal)? = nil,
		applications: (any RunningApplications)? = nil,
		tree: (any AccessibilityTree)? = nil,
		frontmost: (any FrontmostApplication)? = nil,
		trust: (any AccessibilityTrust)? = nil,
		speaker: (any Announcer)? = nil,
		prompter: (any UserPrompter)? = nil
	) -> BridgeServer {
		let handlers = Registry.build(
			factory: VoiceOverAdapterFactory(
				capturePath: capturePath(),
				markerPath: markerPath(),
				lifecycle: lifecycle ?? providerLifecycle(clock: clock),
				tools: tools ?? SubprocessRunner(),
				permissions: permissions ?? permissionBroker(),
				poster: poster ?? eventPoster(),
				applications: applications ?? WorkspaceRunningApplications(),
				layout: layout ?? keyboardLayout(),
				readerModifier: readerModifier ?? readerModifierSetting(),
				readerRestart: readerRestart ?? self.readerRestart(clock: clock),
				changeJournal: changeJournal ?? self.changeJournal(),
				tree: tree ?? accessibilityTree(),
				frontmost: frontmost ?? frontmostApplication(),
				trust: trust ?? accessibilityTrust(),
				announcer: speaker ?? announcer(),
				prompter: prompter ?? userPrompter()
			),
			readerVersion: readerVersion(),
			bridgeVersion: bridgeVersion
		)
		// `attended` and the silence cap's `enabled` are one fact here, derived once.
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
