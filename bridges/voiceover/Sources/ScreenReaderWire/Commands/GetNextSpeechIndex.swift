// ROLE: entity -- `getNextSpeechIndex`'s result. The command has no params.
//
// Pure. Built by the GetNextSpeechIndex handler (entry 13.5).
//
// IT IS THE INDEX THE NEXT UTTERANCE WILL GET, not the last one used, so a
// session marks its place BEFORE acting and then reads the range that its own
// action produced. That is what makes the speech family usable without
// guessing, and it is why the field is a bare integer rather than a range.

public struct NextIndexResult: Codable, Equatable, Sendable {
	public var index: Int

	public init(index: Int) {
		self.index = index
	}
}
