// ROLE: entity, `getNextSpeechIndex`'s result: the index the next utterance will get, not the last one used.

public struct NextIndexResult: Codable, Equatable, Sendable {
	public var index: Int

	public init(index: Int) {
		self.index = index
	}
}
