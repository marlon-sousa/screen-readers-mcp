// ROLE: entity, one thing the reader said, as it travels on the wire.
// `index` is assigned by the bridge, never taken from the capture extension; see Utterance.swift.
// `logPosition` defaults to 0, because VoiceOver has no log to position into.
// `emittedAt` is a wall-clock `YYYY-MM-DD HH:MM:SS.mmm`, not ISO 8601, as in the session transcript.

public struct SpeechEntry: Codable, Equatable, Sendable {
	public var text: String
	public var index: Int
	public var logPosition: Int
	public var emittedAt: String = ""

	public init(text: String, index: Int, logPosition: Int, emittedAt: String = "") {
		self.text = text
		self.index = index
		self.logPosition = logPosition
		self.emittedAt = emittedAt
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		text = try box.decode(String.self, forKey: .text)
		index = try box.decode(Int.self, forKey: .index)
		logPosition = try box.decode(Int.self, forKey: .logPosition)
		emittedAt = try box.decode(String.self, forKey: .emittedAt, orDefault: emittedAt)
	}
}
