// ROLE: entity, `getLastSpeech`'s result; the command has no params.
// An empty buffer answers an empty text, not an error.

public struct LastSpeechResult: Codable, Equatable, Sendable {
	public var text: String
	public var index: Int
	public var logPosition: Int = 0
	public var emittedAt: String = ""

	public init(text: String, index: Int, logPosition: Int = 0, emittedAt: String = "") {
		self.text = text
		self.index = index
		self.logPosition = logPosition
		self.emittedAt = emittedAt
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		text = try box.decode(String.self, forKey: .text)
		index = try box.decode(Int.self, forKey: .index)
		logPosition = try box.decode(Int.self, forKey: .logPosition, orDefault: logPosition)
		emittedAt = try box.decode(String.self, forKey: .emittedAt, orDefault: emittedAt)
	}
}
