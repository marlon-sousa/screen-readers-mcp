// ROLE: port -- the persisted preferences the bridge reads at start-up, without
// either side knowing where they are stored.
//
// IMPLEMENTED BY: UserDefaultsBridgeConfig (adapters), over the Defaults seam;
// FakeBridgeConfig (Tests/Fakes); and LaunchConfig, the headless launcher's
// in-memory one.
// USED BY: Wiring (which endpoint to listen on), the Hello handler (the attended
// flag), the launcher (which starts from the stored values and lets this run's
// flags override them) and the audible session cues (which read their own switch
// on every cue, so a change takes effect at once rather than at the next
// session). The control dialog will be the first thing that WRITES them. Not the
// Session: a session does not read settings, it is handed the ones that shaped
// it.
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

	/// Whether the bridge plays its audible session cues. Defaults to `true`.
	///
	/// A PREFERENCE ABOUT A ROOM, LIKE `attended`, AND NOT ON THE WIRE FOR THE
	/// SAME REASON: the cues exist to tell the person at the machine that
	/// something has taken control of their screen reader, so an agent that could
	/// switch them off would be switching off the one signal that is not addressed
	/// to it. It is here rather than compiled in because a developer running
	/// sessions back to back in a room with other people has a reason to silence
	/// two tones, and no way to say so otherwise.
	///
	/// IT DOES NOT REACH THE SILENCE CAP'S CUES BEING OWED -- the lift still
	/// happens on time whether or not it is marked audibly, because the lift is the
	/// guarantee and the cue is the courtesy (protocol.md §6.1).
	var cuesEnabled: Bool { get set }
}
