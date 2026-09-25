// ROLE: entity, `getFocusInfo`'s result; the command has no params.
// `value` and `appModule` must be present and may be null, so they are decoded by hand: synthesized
// decoding would fold a missing key into nil.
// Without the Accessibility grant `role` and `states` come back empty, indistinguishable from an element with none.

public struct FocusInfoResult: Codable, Equatable, Sendable {
	public var name: String
	public var role: String
	public var states: [String]
	public var value: String?
	public var appModule: String?

	public init(name: String, role: String, states: [String], value: String?, appModule: String?) {
		self.name = name
		self.role = role
		self.states = states
		self.value = value
		self.appModule = appModule
	}

	enum CodingKeys: String, CodingKey {
		case name, role, states, value, appModule
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		name = try box.decode(String.self, forKey: .name)
		role = try box.decode(String.self, forKey: .role)
		states = try box.decode([String].self, forKey: .states)
		value = try box.decodeNil(forKey: .value) ? nil : try box.decode(String.self, forKey: .value)
		appModule = try box.decodeNil(forKey: .appModule) ? nil : try box.decode(String.self, forKey: .appModule)
	}

	public func encode(to encoder: any Encoder) throws {
		var box = encoder.container(keyedBy: CodingKeys.self)
		try box.encode(name, forKey: .name)
		try box.encode(role, forKey: .role)
		try box.encode(states, forKey: .states)
		// encode, not encodeIfPresent: the key must be there, carrying null.
		try box.encode(value, forKey: .value)
		try box.encode(appModule, forKey: .appModule)
	}
}
