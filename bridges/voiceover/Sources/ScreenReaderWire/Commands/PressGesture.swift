// ROLE: entity, `pressGesture`'s params and result, and the per-gesture record the result carries.
// `graceMs` is how long the handler waits after dispatch before reading speech back; 100 is a heuristic
// and 0 opts out.

public struct PressGestureParams: Codable, Equatable, Sendable {
	public var gestures: [String]
	public var graceMs: Int = 100
	public var announce: String = ""

	public init(gestures: [String], graceMs: Int = 100, announce: String = "") {
		self.gestures = gestures
		self.graceMs = graceMs
		self.announce = announce
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		gestures = try box.decode([String].self, forKey: .gestures)
		graceMs = try box.decode(Int.self, forKey: .graceMs, orDefault: graceMs)
		announce = try box.decode(String.self, forKey: .announce, orDefault: announce)
	}
}

public struct GestureResult: Codable, Equatable, Sendable {
	public var pressed: [GesturePress]
	public var speech: [SpeechEntry]
	public var speechFrom: Int
	public var speechTo: Int
	public var state: StateResult?

	public init(
		pressed: [GesturePress],
		speech: [SpeechEntry],
		speechFrom: Int,
		speechTo: Int,
		state: StateResult? = nil
	) {
		self.pressed = pressed
		self.speech = speech
		self.speechFrom = speechFrom
		self.speechTo = speechTo
		self.state = state
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		pressed = try box.decode([GesturePress].self, forKey: .pressed)
		speech = try box.decode([SpeechEntry].self, forKey: .speech)
		speechFrom = try box.decode(Int.self, forKey: .speechFrom)
		speechTo = try box.decode(Int.self, forKey: .speechTo)
		state = try box.decodeIfPresent(StateResult.self, forKey: .state)
	}
}

public struct GesturePress: Codable, Equatable, Sendable {
	public var gesture: String
	public var speechFrom: Int
	public var speechTo: Int

	public init(gesture: String, speechFrom: Int, speechTo: Int) {
		self.gesture = gesture
		self.speechFrom = speechFrom
		self.speechTo = speechTo
	}
}
