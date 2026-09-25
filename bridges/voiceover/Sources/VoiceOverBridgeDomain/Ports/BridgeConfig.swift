// ROLE: port -- the persisted preferences the bridge reads at start-up.
// IMPLEMENTED BY: UserDefaultsBridgeConfig, FakeBridgeConfig and LaunchConfig.
// USED BY: Wiring, the Hello handler, the launcher and the audible session cues; never the Session.
// `attended` and `cuesEnabled` are never on the wire: an agent could otherwise set its own ceiling or silence the cues meant for the human.
public protocol BridgeConfig: AnyObject {
	var connectionMode: ConnectionMode { get set }

	/// A bare name, never a path.
	var endpointName: String { get set }

	var loopbackPort: Int { get set }

	var attended: Bool { get set }

	var cuesEnabled: Bool { get set }
}
