// ROLE: entity -- `getLastSpeech`'s result. The command has no params.
//
// Pure. Built by the GetLastSpeech handler (entry 13.5).
//
// AN EMPTY BUFFER IS AN EMPTY TEXT, NOT AN ERROR: a session that has not made
// the reader say anything yet asks a legitimate question and gets a legitimate
// answer. The type is flat rather than a SpeechEntry because the contract
// defines it that way -- `logPosition` and `emittedAt` default, so a reader with
// no log or no clock can still answer.

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
