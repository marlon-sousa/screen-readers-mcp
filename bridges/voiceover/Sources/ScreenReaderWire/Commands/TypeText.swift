// ROLE: entity, `typeText`'s params and result.
// The text is never logged, because this is how a secret is entered.

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
