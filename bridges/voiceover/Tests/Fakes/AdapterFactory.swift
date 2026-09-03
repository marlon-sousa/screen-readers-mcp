// A hand-written stateful fake for the AdapterFactory port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/AdapterFactory.swift.
//
// It records the mode it was asked for -- which is what proves the handshake
// passed the CLIENT's mode through rather than a default -- and can be told to
// refuse, because refusing a mode is part of this port's contract and the hello
// handler has to turn that refusal into an error the agent can read.
//
// THE SPEECH SOURCE IT BUILDS IS EXPOSED, because half of what the handshake has
// to get right is invisible in the AdapterSet: that capture was STARTED, against
// the buffer the context ended up holding, and after the set was installed so
// teardown can stop it.

import ScreenReaderWire
import VoiceOverBridgeDomain

public final class FakeAdapterFactory: AdapterFactory {
	public private(set) var builtFor: [CaptureMode] = []
	/// The source every set this factory builds carries, so a test can ask it
	/// what the handshake did to it.
	public let speechSource = FakeSpeechSource()
	/// The same, for the two collaborators 13.6 added: the handshake opens the
	/// marker channel and points the reader at the capture voice, and both of
	/// those are invisible in the AdapterSet itself.
	public let silenceControl = FakeSilenceControl()
	public let providerLifecycle: FakeProviderLifecycle
	/// The same again for 13.7's two: a session test asserts what was DISPATCHED,
	/// and that is invisible in the AdapterSet the handshake hands back.
	public let gestureSender = FakeGestureSender()
	public let readerLiveness = FakeReaderLiveness()
	/// And 13.8's two, for the same reason -- plus one this file cannot leave
	/// implicit: the broker records whether the Accessibility grant was ever
	/// REQUESTED, and a session test asserting that a run of COMMAND-NAME gestures
	/// never asked for it is asserting the entry's whole claim.
	public let textTyper = FakeTextTyper()
	public let permissions = FakePermissionBroker()
	/// And 13.17's one, exposed for the reason the gesture sender is: a session
	/// test asserts WHICH ROUTE a gesture id took, and "the chord went to the
	/// system rather than to the reader" is invisible in the AdapterSet.
	public let keyPresser = FakeKeyPresser()
	/// And 13.25's one, exposed so a session test can put this machine on a
	/// different VoiceOver modifier -- Caps Lock, or one that cannot be read --
	/// and assert that `vo+m` is refused over a real wire with nothing pressed.
	public let readerModifier = FakeReaderModifierSetting()
	/// And 13.26's, exposed so a session test can put this machine on one with no
	/// AppleScript control at all and assert that a session is still established.
	public let readerScripting = FakeReaderScriptingSetting()
	/// The WRITE side of the modifier, exposed so a session test can drive a
	/// Caps-Lock machine through the replacement and assert the ORDER of the
	/// writes -- ours, then theirs, before the handshake returns.
	public let readerModifierStore = FakeReaderModifierStore()
	/// The one collaborator that takes somebody's screen reader away. Exposed
	/// because the assertion worth making about it is usually that it was NOT
	/// called: an ordinary handshake restarts nothing.
	public let readerRestart = FakeReaderRestart()
	/// What this session changed and put back. Exposed so a session test can
	/// assert the thing the journal exists for -- that nothing is left OPEN.
	public let changeJournal = FakeChangeJournal()
	/// And 13.9's one. Exposed like the rest so a session-level test can assert
	/// what a `getFocusInfo` off the wire actually read -- and, beside
	/// `permissions` above, that answering focus asked the broker nothing.
	public let focusInspector = FakeFocusInspector()
	/// And 13.10's two, exposed for the sharpest reason of the lot: what the human
	/// at the machine was TOLD, and what they were ASKED, are the two things a
	/// session test has to be able to assert about a silent run -- and neither is
	/// visible anywhere else, because both go out of this process rather than into
	/// a result.
	public let announcer = FakeAnnouncer()
	public let userPrompter = FakeUserPrompter()
	/// When set, `build` throws it instead of answering.
	public var refusal: AdapterFactoryError?

	/// THE MACHINE THIS FACTORY STANDS FOR IS HEALTHY BY DEFAULT, AND SINCE 13.20
	/// THAT INCLUDES A READER THAT SPEAKS. The handshake's last rung presses the
	/// capture probe and requires the utterance to arrive, so a factory whose
	/// reader was mute would be a machine no `hello` could complete on -- and
	/// every test in HelloTests would fail for a reason none of them is about.
	/// `captureProbeSpeaks: false` is how a test asks for the machine where
	/// nothing comes back, which is the failure 13.20 exists to report.
	///
	/// The wiring itself is `Support/ReaderEdge.swift`'s, called rather than
	/// copied: `fakeAdapterSet` needs the same behaviour, and two definitions of
	/// "a working reader" would differ the first time the probe changed.
	public init(
		refusal: AdapterFactoryError? = nil,
		providerLifecycle: FakeProviderLifecycle = FakeProviderLifecycle(),
		captureProbeSpeaks: Bool = true
	) {
		self.refusal = refusal
		self.providerLifecycle = providerLifecycle
		if captureProbeSpeaks {
			answerTheCaptureProbe(pressing: gestureSender, speaking: speechSource)
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
			gestureSender: gestureSender,
			readerLiveness: readerLiveness,
			textTyper: textTyper,
			keyPresser: keyPresser,
			readerModifier: readerModifier,
			readerScripting: readerScripting,
			readerModifierStore: readerModifierStore,
			readerRestart: readerRestart,
			changeJournal: changeJournal,
			permissions: permissions,
			focusInspector: focusInspector,
			announcer: announcer,
			userPrompter: userPrompter
		)
	}
}
