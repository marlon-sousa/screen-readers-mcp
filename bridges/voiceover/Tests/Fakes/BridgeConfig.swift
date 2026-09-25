import VoiceOverBridgeDomain

public final class FakeBridgeConfig: BridgeConfig {
	public var connectionMode: ConnectionMode
	public var endpointName: String
	public var loopbackPort: Int
	public var attended: Bool
	public var cuesEnabled: Bool

	public init(
		connectionMode: ConnectionMode = .default,
		endpointName: String = defaultEndpointName,
		loopbackPort: Int = defaultLoopbackPort,
		attended: Bool = true,
		cuesEnabled: Bool = true
	) {
		self.connectionMode = connectionMode
		self.endpointName = endpointName
		self.loopbackPort = loopbackPort
		self.attended = attended
		self.cuesEnabled = cuesEnabled
	}
}
