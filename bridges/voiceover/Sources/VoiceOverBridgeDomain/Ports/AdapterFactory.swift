// ROLE: port -- builds the mode-specific collaborators, once, after `hello`.
// IMPLEMENTED BY: VoiceOverAdapterFactory; FakeAdapterFactory.
// BUILT BY: Wiring.
// USED BY: the Hello handler, exactly once per session.

import ScreenReaderWire

public struct AdapterSet {
	public let mode: CaptureMode

	public let speechSource: any SpeechSource

	/// Present in both modes: a live session still opens the channel so the user's own voice reaches the extension for pass-through.
	public let silenceControl: any SilenceControl

	public let providerLifecycle: any ProviderLifecycle

	public let readerLiveness: any ReaderLiveness

	public let textTyper: any TextTyper

	public let keyPresser: any KeyPresser

	public let readerModifier: any ReaderModifierSetting

	/// Used only by the registration rung, because macOS publishes a newly registered capture voice only after VoiceOver restarts.
	public let readerRestart: any ReaderRestart

	public let changeJournal: any ChangeJournal

	public let permissions: any PermissionBroker

	/// Nothing on this path may request a permission.
	public let focusInspector: any FocusInspector

	public let announcer: any Announcer

	public let userPrompter: any UserPrompter

	public init(
		mode: CaptureMode,
		speechSource: any SpeechSource,
		silenceControl: any SilenceControl,
		providerLifecycle: any ProviderLifecycle,
		readerLiveness: any ReaderLiveness,
		textTyper: any TextTyper,
		keyPresser: any KeyPresser,
		readerModifier: any ReaderModifierSetting,
		readerRestart: any ReaderRestart,
		changeJournal: any ChangeJournal,
		permissions: any PermissionBroker,
		focusInspector: any FocusInspector,
		announcer: any Announcer,
		userPrompter: any UserPrompter
	) {
		self.mode = mode
		self.speechSource = speechSource
		self.silenceControl = silenceControl
		self.providerLifecycle = providerLifecycle
		self.readerLiveness = readerLiveness
		self.textTyper = textTyper
		self.keyPresser = keyPresser
		self.readerModifier = readerModifier
		self.readerRestart = readerRestart
		self.changeJournal = changeJournal
		self.permissions = permissions
		self.focusInspector = focusInspector
		self.announcer = announcer
		self.userPrompter = userPrompter
	}
}

/// A mode this build cannot carry out.
public struct AdapterFactoryError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol AdapterFactory: AnyObject {
	/// Refusing is part of the contract: a bridge that cannot carry out a mode says so at the handshake.
	func build(mode: CaptureMode) throws -> AdapterSet
}
