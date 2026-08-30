// ROLE: entity -- `typeText`'s params and result.
//
// Pure. Built by the TypeText handler (entry 13.8), which synthesizes keystrokes
// rather than setting a field's value, so the reader speaks as a human typing
// would make it speak.
//
// `graceMs` DEFAULTS TO 0 HERE AND TO 100 FOR A GESTURE, and the difference is
// not an oversight: typing produces its speech as the keys land, while a gesture
// produces it afterwards. The type names are the contract's -- TypeParams, not
// TypeTextParams -- so the binding and the schema can be compared by name.
//
// THE TEXT IS NEVER LOGGED, because this is exactly how a secret is entered
// (protocol.md §5). That obligation belongs to the transcript adapter; it is
// noted here because this is where a reader meets the field.

public struct TypeParams: Codable, Equatable, Sendable {
	public var text: String
	public var graceMs: Int = 0
	public var announce: String = ""

	public init(text: String, graceMs: Int = 0, announce: String = "") {
		self.text = text
		self.graceMs = graceMs
		self.announce = announce
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		text = try box.decode(String.self, forKey: .text)
		graceMs = try box.decode(Int.self, forKey: .graceMs, orDefault: graceMs)
		announce = try box.decode(String.self, forKey: .announce, orDefault: announce)
	}
}

public struct TypeResult: Codable, Equatable, Sendable {
	/// How many characters were typed -- never the characters themselves.
	public var typed: Int
	public var speech: [SpeechEntry]
	public var speechFrom: Int
	public var speechTo: Int
	public var state: StateResult?

	public init(typed: Int, speech: [SpeechEntry], speechFrom: Int, speechTo: Int, state: StateResult? = nil) {
		self.typed = typed
		self.speech = speech
		self.speechFrom = speechFrom
		self.speechTo = speechTo
		self.state = state
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		typed = try box.decode(Int.self, forKey: .typed)
		speech = try box.decode([SpeechEntry].self, forKey: .speech)
		speechFrom = try box.decode(Int.self, forKey: .speechFrom)
		speechTo = try box.decode(Int.self, forKey: .speechTo)
		state = try box.decodeIfPresent(StateResult.self, forKey: .state)
	}
}
