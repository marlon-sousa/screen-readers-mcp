// ROLE: entity -- `pressGesture`'s params and result, and the per-gesture record
// the result carries.
//
// Pure. Built by the PressGesture handler (entry 13.7), which sends the
// gestures through the reader's own input route and slices the speech buffer.
//
// `graceMs` IS THE GRACE WINDOW OF protocol.md §7.3, AND ITS 100 IS A HEURISTIC
// RATHER THAN A CONSTANT TO TRUST: it is how long the handler waits after
// dispatching before reading back what was said, and a heavier document moves
// it -- which is exactly why it is a parameter. `0` opts out.

public struct PressGestureParams: Codable, Equatable, Sendable {
	public var gestures: [String]
	public var graceMs: Int = 100
	/// Spoken to the human before the gesture is sent, when a session wants the
	/// machine's owner to know what is about to happen.
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
	/// Absent when the reader cannot report its state -- which is this bridge's
	/// answer: VoiceOver's 45 toggles are richly drivable and almost none is
	/// readable (spec 0046 part 2), so `state` stays nil here and the `state`
	/// capability is not advertised.
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

/// One gesture, and the half-open speech range it produced. The range is what
/// makes a multi-gesture call readable: each press owns its own utterances.
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
