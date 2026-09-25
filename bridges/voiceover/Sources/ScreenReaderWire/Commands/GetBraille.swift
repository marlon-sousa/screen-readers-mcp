// ROLE: entity, `getBraille`'s params and result, and the entry the result carries.
// VoiceOver's scripting model exposes only the braille window's `enabled`, so this bridge does not advertise `braille`.

public struct GetBrailleParams: Codable, Equatable, Sendable {
	public var sinceIndex: Int

	public init(sinceIndex: Int) {
		self.sinceIndex = sinceIndex
	}
}

public struct BrailleResult: Codable, Equatable, Sendable {
	public var entries: [BrailleEntry]
	public var fromIndex: Int
	public var toIndex: Int

	public init(entries: [BrailleEntry], fromIndex: Int, toIndex: Int) {
		self.entries = entries
		self.fromIndex = fromIndex
		self.toIndex = toIndex
	}
}

public struct BrailleEntry: Codable, Equatable, Sendable {
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
