// ROLE: leaf adapter implementing the Defaults seam over `UserDefaults`.
// BUILT BY: Wiring.
// USED BY: UserDefaultsBridgeConfig.
// Reads use `object(forKey:)`, because `bool(forKey:)` answers false for a key never set and the seam must return nil for it.

import Foundation

public final class UserDefaultsStore: Defaults {
	private let store: UserDefaults

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
