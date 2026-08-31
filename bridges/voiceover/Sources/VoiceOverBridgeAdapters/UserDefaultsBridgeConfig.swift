// ROLE: adapter -- IMPLEMENTS the BridgeConfig domain port over the Defaults
// seam. It owns the key names, the defaults, and what to do with a stored value
// that no longer makes sense.
//
// BUILT BY: Wiring, once per process. USED BY: the launcher, which starts from
// these values and lets this run's flags override them; Wiring itself (which
// listener to build); the Hello handler (the attended flag); and the audible cues
// (their own switch). The control dialog will be the first thing that WRITES
// them.
//
// EVERY READ IS FROM THE STORE, AND EVERY WRITE GOES STRAIGHT TO IT. There is no
// cached copy, deliberately: something writes a value and the next thing that
// reads it -- possibly the accept loop, on another thread -- must see it. A cache
// here would be a second source of truth for a handful of scalars.
//
// A STORED VALUE THAT NO LONGER PARSES FALLS BACK TO THE DEFAULT, and is not
// repaired in place. A connection mode this build does not have, a port outside
// the legal range, an endpoint name that is empty: each is a machine that was
// configured by an older build or edited by hand, and the safe answer is the
// shipped default -- which is also what an unconfigured machine gets, so there is
// one behaviour to reason about rather than two. Rewriting the store on a READ
// would mean that merely LOOKING at somebody's settings edited them.
//
// THE ENDPOINT NAME IS A STORED SETTING, NOT ONLY A KIND, and that is board entry
// 11.37 arriving cheaply here: lane 1 builds its listener from a CONSTANT, so the
// override that exists on the dialing side is, in practice, a way to make the two
// halves disagree silently. The board says lane 3 gets the field cheaply if it is
// designed in and expensively if it is added, so it is designed in at the layer
// that holds it -- and on POSIX the same value accepts an absolute socket path,
// which the listener already honours because `LocalSocketPath` treats anything
// with a separator in it as a path the user meant literally. What is still owed
// is a way for a human to EDIT it without a `defaults` command, and that belongs
// to the control dialog.

import VoiceOverBridgeDomain

public final class UserDefaultsBridgeConfig: BridgeConfig {
	/// The stored keys, spelled once. Prefixed because `UserDefaults.standard` is
	/// shared with everything else this application will ever store.
	enum Key {
		static let connectionMode = "bridge.connectionMode"
		static let endpointName = "bridge.endpointName"
		static let loopbackPort = "bridge.loopbackPort"
		static let attended = "bridge.attended"
		static let cuesEnabled = "bridge.cuesEnabled"
	}

	private let defaults: any Defaults

	public init(defaults: any Defaults) {
		self.defaults = defaults
	}

	public var connectionMode: ConnectionMode {
		get {
			guard let raw = defaults.string(Key.connectionMode), let mode = ConnectionMode(rawValue: raw)
			else {
				return .default
			}
			return mode
		}
		set { defaults.set(Key.connectionMode, newValue.rawValue) }
	}

	public var endpointName: String {
		get {
			guard let name = defaults.string(Key.endpointName), !name.isEmpty else {
				return defaultEndpointName
			}
			return name
		}
		set { defaults.set(Key.endpointName, newValue) }
	}

	public var loopbackPort: Int {
		get {
			// A PORT OUTSIDE THE LEGAL RANGE IS THE DEFAULT, not a bind that fails
			// with `invalid argument` at the moment somebody presses Start. 0 is
			// excluded on purpose: it means "any free port" to the kernel, which is
			// useless for an endpoint a server has to dial by number.
			guard let port = defaults.integer(Key.loopbackPort), (1...65535).contains(port) else {
				return defaultLoopbackPort
			}
			return port
		}
		set { defaults.set(Key.loopbackPort, newValue) }
	}

	public var attended: Bool {
		// DEFAULTS TO TRUE, and the costs are not symmetric: a machine nobody has
		// configured is not a machine we may assume is empty (spec 0035).
		get { defaults.boolean(Key.attended) ?? true }
		set { defaults.set(Key.attended, newValue) }
	}

	public var cuesEnabled: Bool {
		get { defaults.boolean(Key.cuesEnabled) ?? true }
		set { defaults.set(Key.cuesEnabled, newValue) }
	}
}
