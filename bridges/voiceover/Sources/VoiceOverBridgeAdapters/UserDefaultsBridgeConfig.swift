// ROLE: adapter implementing the BridgeConfig port over the Defaults seam; it owns the key names, the defaults and the fallback for a stored value that no longer parses.
// BUILT BY: Wiring, once per process.
// USED BY: the launcher, Wiring, the Hello handler and the audible cues.
// No cached copy: the accept loop, on another thread, must see a write at once.
// A stored value that no longer parses reads as the default and is never repaired on read, so looking at settings never edits them.

import VoiceOverBridgeDomain

public final class UserDefaultsBridgeConfig: BridgeConfig {
	/// Prefixed because `UserDefaults.standard` is shared with everything else this application stores.
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
			// Out of range reads as the default; 0 is excluded because it means any free port, which a server cannot dial.
			guard let port = defaults.integer(Key.loopbackPort), (1...65535).contains(port) else {
				return defaultLoopbackPort
			}
			return port
		}
		set { defaults.set(Key.loopbackPort, newValue) }
	}

	public var attended: Bool {
		// Defaults to true: an unconfigured machine may not be assumed empty.
		get { defaults.boolean(Key.attended) ?? true }
		set { defaults.set(Key.attended, newValue) }
	}

	public var cuesEnabled: Bool {
		get { defaults.boolean(Key.cuesEnabled) ?? true }
		set { defaults.set(Key.cuesEnabled, newValue) }
	}
}
