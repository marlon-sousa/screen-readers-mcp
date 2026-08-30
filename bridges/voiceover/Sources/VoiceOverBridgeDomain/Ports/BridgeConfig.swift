// ROLE: port -- the persisted preferences the bridge reads at start-up and the
// control dialog writes, without either side knowing where they are stored.
//
// IMPLEMENTED BY: FakeBridgeConfig (Tests/Fakes) today; the real
// UserDefaults-backed adapter arrives with the control dialog (13.10), which is
// the first thing that can change one of these values.
// USED BY: Wiring (which endpoint to listen on) and the Hello handler (the
// attended flag). Not by the Session: a session does not read settings, it is
// handed the ones that shaped it.
//
// THE ATTENDED FLAG IS A FACT ABOUT THE ROOM, NOT ABOUT THE BRIDGE, and it is
// deliberately not on the wire (spec 0035): the agent declares a persona, and an
// agent that could also declare that nobody is listening would be setting its
// own ceiling. It defaults to attended because the costs are not symmetric -- a
// machine nobody has configured is not a machine we may assume is empty.
public protocol BridgeConfig: AnyObject {
	/// Which of the two transports to listen on (protocol.md §1).
	var connectionMode: ConnectionMode { get set }

	/// The local endpoint's bare NAME -- never a path. What the name resolves to
	/// is the host's business, which is the whole point of spec 0044.
	var endpointName: String { get set }

	/// The loopback port, used only when `connectionMode` is `.loopbackTcp`.
	var loopbackPort: Int { get set }

	/// Whether a human is expected at this machine. Defaults to `true`.
	var attended: Bool { get set }
}
