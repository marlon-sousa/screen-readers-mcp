// ROLE: entity -- one thing the reader said, as it travels on the wire.
//
// Pure. Carried by SpeechResult, GestureResult and TypeResult -- three shapes in
// three files, which is why it is a file of its own rather than living with any
// of them.
//
// `index` IS THE BRIDGE'S OWN NUMBER, NOT THE READER'S. On macOS the capture
// extension's sequence counter restarts whenever the system relaunches it
// (measured, spec 0041 A4), so entry 13.5's SpeechBuffer assigns these indices
// and discards the extension's. Nothing in this file can enforce that; the
// header says it because the field looks equally trustworthy either way.
//
// `logPosition` IS AN NVDA COORDINATE, and this bridge has no log to position
// into -- VoiceOver emits no diagnostic log of its own. It stays in the shape
// because the shape is the contract's, and it defaults to 0, which is what the
// Python binding does for a reader that cannot answer it.
//
// `emittedAt` is ISO 8601 with a timezone (spec 0028), carried as a String
// rather than a Date: the contract's field is a formatted instant, and parsing
// it here would make this binding responsible for a calendar it has no use for.

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
