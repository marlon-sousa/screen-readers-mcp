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
	/// When set, `build` throws it instead of answering.
	public var refusal: AdapterFactoryError?

	public init(refusal: AdapterFactoryError? = nil) {
		self.refusal = refusal
	}

	public func build(mode: CaptureMode) throws -> AdapterSet {
		builtFor.append(mode)
		if let refusal { throw refusal }
		return AdapterSet(mode: mode, speechSource: speechSource)
	}
}
