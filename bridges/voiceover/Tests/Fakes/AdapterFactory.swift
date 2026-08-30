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
	/// REQUESTED, and a session test asserting that a run of gestures never asked
	/// for it is asserting the entry's whole claim.
	public let textTyper = FakeTextTyper()
	public let permissions = FakePermissionBroker()
	/// When set, `build` throws it instead of answering.
	public var refusal: AdapterFactoryError?

	public init(
		refusal: AdapterFactoryError? = nil,
		providerLifecycle: FakeProviderLifecycle = FakeProviderLifecycle()
	) {
		self.refusal = refusal
		self.providerLifecycle = providerLifecycle
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
			permissions: permissions
		)
	}
}
