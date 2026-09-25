import ScreenReaderWire
import VoiceOverBridgeDomain

public final class FakeAdapterFactory: AdapterFactory {
	public private(set) var builtFor: [CaptureMode] = []
	public let speechSource = FakeSpeechSource()
	public let silenceControl = FakeSilenceControl()
	public let providerLifecycle: FakeProviderLifecycle
	public let readerLiveness = FakeReaderLiveness()
	public let textTyper = FakeTextTyper()
	public let permissions = FakePermissionBroker()
	public let keyPresser = FakeKeyPresser()
	public let readerModifier = FakeReaderModifierSetting()
	public let readerRestart = FakeReaderRestart()
	public let changeJournal = FakeChangeJournal()
	public let focusInspector = FakeFocusInspector()
	public let announcer = FakeAnnouncer()
	public let userPrompter = FakeUserPrompter()
	public var refusal: AdapterFactoryError?

	/// Healthy by default, including a reader that answers the capture probe; `captureProbeSpeaks: false` gives the machine where nothing comes back.
	public init(
		refusal: AdapterFactoryError? = nil,
		providerLifecycle: FakeProviderLifecycle = FakeProviderLifecycle(),
		captureProbeSpeaks: Bool = true
	) {
		self.refusal = refusal
		self.providerLifecycle = providerLifecycle
		if captureProbeSpeaks {
			answerTheCaptureProbe(pressing: keyPresser, speaking: speechSource)
		}
	}

	public func build(mode: CaptureMode) throws -> AdapterSet {
		builtFor.append(mode)
		if let refusal { throw refusal }
		return AdapterSet(
			mode: mode,
			speechSource: speechSource,
			silenceControl: silenceControl,
			providerLifecycle: providerLifecycle,
			readerLiveness: readerLiveness,
			textTyper: textTyper,
			keyPresser: keyPresser,
			readerModifier: readerModifier,
			readerRestart: readerRestart,
			changeJournal: changeJournal,
			permissions: permissions,
			focusInspector: focusInspector,
			announcer: announcer,
			userPrompter: userPrompter
		)
	}
}
