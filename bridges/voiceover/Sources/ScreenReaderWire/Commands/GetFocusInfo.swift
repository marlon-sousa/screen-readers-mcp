// ROLE: entity -- `getFocusInfo`'s result. The command has no params.
//
// Pure. Built by the GetFocusInfo handler (entry 13.9).
//
// TWO FIELDS ARE REQUIRED AND NULLABLE, WHICH IS A THIRD STATE THE SYNTHESIZED
// DECODER WOULD ERASE. `value` and `appModule` must be PRESENT and may be null:
// "the element has no value" is an answer, and "the frame forgot the field" is a
// fault. Swift's synthesized `init(from:)` decodes an Optional with
// decodeIfPresent, which folds those two into nil -- so this file decodes them
// by hand. The Go binding draws the same line with a pointer and no `omitempty`.
//
// THIS BRIDGE ANSWERS DIFFERENTLY DEPENDING ON A PERMISSION (spec 0046's honest
// limits): richer with Accessibility granted, thinner without, and the shape has
// nowhere to say which route answered. An agent reading empty `role` and
// `states` cannot tell "no grant" from "the element has none" -- which is why
// the guidance document and the control dialog carry that, not this struct.

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

	// Spelled out rather than synthesized: a type that writes BOTH halves of
	// Codable gets no synthesized keys, and the names are the wire's own.
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
