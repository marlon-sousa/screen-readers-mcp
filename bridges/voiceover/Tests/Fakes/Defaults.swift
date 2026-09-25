import VoiceOverBridgeAdapters

public final class FakeDefaults: Defaults {
	public var values: [String: Any] = [:]

	public init(_ values: [String: Any] = [:]) {
		self.values = values
	}

	public func string(_ key: String) -> String? { values[key] as? String }

	public func integer(_ key: String) -> Int? { values[key] as? Int }

	public func boolean(_ key: String) -> Bool? { values[key] as? Bool }

	public func set(_ key: String, _ value: String) { values[key] = value }

	public func set(_ key: String, _ value: Int) { values[key] = value }

	public func set(_ key: String, _ value: Bool) { values[key] = value }
}
