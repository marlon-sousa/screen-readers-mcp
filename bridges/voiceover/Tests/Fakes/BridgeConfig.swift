// A hand-written stateful fake for the BridgeConfig port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/BridgeConfig.swift.
//
// An in-memory settings store. It defaults to what a machine nobody has
// configured would answer -- the local endpoint, the shipped name, attended --
// so a test that does not care about settings does not have to state them, and a
// test that changes one is visibly changing it.

import VoiceOverBridgeDomain

public final class FakeBridgeConfig: BridgeConfig {
	public var connectionMode: ConnectionMode
	public var endpointName: String
	public var loopbackPort: Int
	public var attended: Bool

	public init(
		connectionMode: ConnectionMode = .default,
		endpointName: String = defaultEndpointName,
		loopbackPort: Int = defaultLoopbackPort,
		attended: Bool = true
	) {
		self.connectionMode = connectionMode
		self.endpointName = endpointName
		self.loopbackPort = loopbackPort
		self.attended = attended
	}
}
