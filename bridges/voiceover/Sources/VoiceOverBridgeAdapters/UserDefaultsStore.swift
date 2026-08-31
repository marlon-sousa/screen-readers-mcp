// ROLE: LEAF adapter -- IMPLEMENTS the Defaults seam over `UserDefaults`. Real
// persistence, no decisions.
//
// BUILT BY: Wiring. USED BY: UserDefaultsBridgeConfig, which holds every
// decision about what is stored and what it means.
//
// NO TEST FILE (leaf): there is nothing here `UserDefaults` does not already
// guarantee, and a test would be testing Apple's code with our machine's
// preferences as the fixture.
//
// `object(forKey:)` RATHER THAN `bool(forKey:)`, and that is the one thing in
// this file worth knowing: `UserDefaults.bool(forKey:)` answers `false` for a key
// that was never set, which would make "the human turned the cues off" and "the
// human has never opened this dialog" the same reading. The seam promises an
// optional for exactly that reason, so the presence of the key has to be checked
// here.

import Foundation

public final class UserDefaultsStore: Defaults {
	private let store: UserDefaults

	/// The standard defaults for this application by default. Injectable so the
	/// launcher and a diagnosis can point at a suite of their own without this
	/// class knowing why.
	public init(store: UserDefaults = .standard) {
		self.store = store
	}

	public func string(_ key: String) -> String? {
		store.object(forKey: key) as? String
	}

	public func integer(_ key: String) -> Int? {
		guard let value = store.object(forKey: key) else { return nil }
		return (value as? NSNumber)?.intValue
	}

	public func boolean(_ key: String) -> Bool? {
		guard let value = store.object(forKey: key) else { return nil }
		return (value as? NSNumber)?.boolValue
	}

	public func set(_ key: String, _ value: String) {
		store.set(value, forKey: key)
	}

	public func set(_ key: String, _ value: Int) {
		store.set(value, forKey: key)
	}

	public func set(_ key: String, _ value: Bool) {
		store.set(value, forKey: key)
	}
}
