// ROLE: entity -- `getSpeech`'s params and result.
//
// Pure. Built by the GetSpeech handler (entry 13.5), reading the SpeechBuffer.
//
// THE RANGE IS HALF-OPEN, `fromIndex` INCLUSIVE AND `toIndex` EXCLUSIVE, so the
// next call passes the previous `toIndex` as `sinceIndex` and nothing is read
// twice or skipped. That is the property the whole speech family is built on.

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
