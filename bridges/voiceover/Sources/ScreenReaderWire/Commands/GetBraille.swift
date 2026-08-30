// ROLE: entity -- `getBraille`'s params and result, and the entry the result
// carries.
//
// Pure. This bridge implements NONE of it: VoiceOver's scripting object model
// exposes a braille window with exactly one property, `enabled`, and no way to
// read what is on the display (spec 0046, part 2). So `braille` is a capability
// this bridge does not advertise, and the gate makes that a first-class answer
// rather than a broken command -- spec 0013's whole point.
//
// THE SHAPE IS STILL BOUND, because the binding renders the CONTRACT and not
// this reader's subset. See Command.swift's header for why that is the rule.

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

/// One braille display update, indexed and half-open exactly as speech is.
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
