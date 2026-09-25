// ROLE: entity, `getSpeech`'s params and result.
// The range is half-open, so the next call passes the previous `toIndex` as `sinceIndex`.

public struct GetSpeechParams: Codable, Equatable, Sendable {
	public var sinceIndex: Int

	public init(sinceIndex: Int) {
		self.sinceIndex = sinceIndex
	}
}

public struct SpeechResult: Codable, Equatable, Sendable {
	public var entries: [SpeechEntry]
	public var fromIndex: Int
	public var toIndex: Int

	public init(entries: [SpeechEntry], fromIndex: Int, toIndex: Int) {
		self.entries = entries
		self.fromIndex = fromIndex
		self.toIndex = toIndex
	}
}
