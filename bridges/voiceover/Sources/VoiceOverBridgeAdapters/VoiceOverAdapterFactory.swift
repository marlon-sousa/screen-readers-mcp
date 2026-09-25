// ROLE: adapter implementing the AdapterFactory port; the only place that knows what a capture mode means, since the mode is known only after `hello`.
// BUILT BY: Wiring. USED BY: the Hello handler, once per session.

import ScreenReaderWire
import VoiceOverBridgeDomain

public final class VoiceOverAdapterFactory: AdapterFactory {
	private let capturePath: String
	private let markerPath: String
	private let lifecycle: any ProviderLifecycle
	private let tools: any ProcessRunner
	private let permissions: any PermissionBroker
	private let poster: any EventPoster
	private let applications: any RunningApplications
	private let layout: any KeyboardLayout
	private let readerModifier: any ReaderModifierSetting
	private let readerRestart: any ReaderRestart
	private let changeJournal: any ChangeJournal
	private let tree: any AccessibilityTree
	private let frontmost: any FrontmostApplication
	private let trust: any AccessibilityTrust
	private let announcer: any Announcer
	private let prompter: any UserPrompter

	/// Everything is injected with no defaults: Wiring alone reads the environment, and no test may build the real poster, broker, announcer, prompter or lifecycle, which type, prompt, speak or change the user's voice.
	public init(
		capturePath: String,
		markerPath: String,
		lifecycle: any ProviderLifecycle,
		tools: any ProcessRunner,
		permissions: any PermissionBroker,
		poster: any EventPoster,
		applications: any RunningApplications,
		layout: any KeyboardLayout,
		readerModifier: any ReaderModifierSetting,
		readerRestart: any ReaderRestart,
		changeJournal: any ChangeJournal,
		tree: any AccessibilityTree,
		frontmost: any FrontmostApplication,
		trust: any AccessibilityTrust,
		announcer: any Announcer,
		prompter: any UserPrompter
	) {
		self.capturePath = capturePath
		self.markerPath = markerPath
		self.lifecycle = lifecycle
		self.tools = tools
		self.permissions = permissions
		self.poster = poster
		self.applications = applications
		self.layout = layout
		self.readerModifier = readerModifier
		self.readerRestart = readerRestart
		self.changeJournal = changeJournal
		self.tree = tree
		self.frontmost = frontmost
		self.trust = trust
		self.announcer = announcer
		self.prompter = prompter
	}

	public func build(mode: CaptureMode) throws -> AdapterSet {
		// Source and silence control are per session: shared, one session's teardown would lift another's silence, and utterances would go to whichever buffer read first.
		AdapterSet(
			mode: mode,
			speechSource: ContainerFileSpeechSource(tailer: FileLineTailer(path: capturePath)),
			silenceControl: MarkerFileSilenceControl(path: markerPath),
			providerLifecycle: lifecycle,
			readerLiveness: VoiceOverLiveness(applications: applications, tools: tools),
			textTyper: AccessibilityTextTyper(poster: poster),
			keyPresser: CGKeystrokePresser(layout: layout, poster: poster),
			// Shared; it must not cache its answer (see the ReaderModifierSetting port).
			readerModifier: readerModifier,
			// Shared and built once, in Wiring: the one object that can take somebody's screen reader away.
			readerRestart: readerRestart,
			changeJournal: changeJournal,
			permissions: permissions,
			// Handed `trust`, never `permissions`, so reading focus can never raise a consent dialog.
			focusInspector: VoiceOverFocusInspector(
				tree: tree, frontmost: frontmost, trust: trust
			),
			// Shared: two announcers would talk over each other, and two prompters would each hold half the tickets.
			announcer: announcer,
			userPrompter: prompter
		)
	}
}
