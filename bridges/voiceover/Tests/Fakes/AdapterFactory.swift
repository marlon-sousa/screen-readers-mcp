// A hand-written stateful fake for the AdapterFactory port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/AdapterFactory.swift.
//
// It records the mode it was asked for -- which is what proves the handshake
// passed the CLIENT's mode through rather than a default -- and can be told to
// refuse, because refusing a mode is part of this port's contract and the hello
// handler has to turn that refusal into an error the agent can read.

import ScreenReaderWire
import VoiceOverBridgeDomain

public final class FakeAdapterFactory: AdapterFactory {
	public private(set) var builtFor: [CaptureMode] = []
	/// When set, `build` throws it instead of answering.
	public var refusal: AdapterFactoryError?

	public init(refusal: AdapterFactoryError? = nil) {
		self.refusal = refusal
	}

	public func build(mode: CaptureMode) throws -> AdapterSet {
		builtFor.append(mode)
		if let refusal { throw refusal }
		return AdapterSet(mode: mode)
	}
}
