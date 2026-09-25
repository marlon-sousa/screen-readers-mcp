// ROLE: entity, `waitForSpeech`'s params and result.
// `found == false` is a normal answer, not an error.

public struct WaitForSpeechParams: Codable, Equatable, Sendable {
	public var text: String
	/// nil means from wherever the buffer is now.
	public var afterIndex: Int?
	public var timeout: Double = 5.0

	public init(text: String, afterIndex: Int? = nil, timeout: Double = 5.0) {
		self.text = text
		self.afterIndex = afterIndex
		self.timeout = timeout
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		text = try box.decode(String.self, forKey: .text)
		afterIndex = try box.decodeIfPresent(Int.self, forKey: .afterIndex)
		timeout = try box.decode(Double.self, forKey: .timeout, orDefault: timeout)
	}
}

public struct WaitForSpeechResult: Codable, Equatable, Sendable {
	public var found: Bool
	public var index: Int
	public var text: String
	public var logPosition: Int = 0
	public var emittedAt: String = ""

	public init(found: Bool, index: Int, text: String, logPosition: Int = 0, emittedAt: String = "") {
		self.found = found
		self.index = index
		self.text = text
		self.logPosition = logPosition
		self.emittedAt = emittedAt
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		found = try box.decode(Bool.self, forKey: .found)
		index = try box.decode(Int.self, forKey: .index)
		text = try box.decode(String.self, forKey: .text)
		logPosition = try box.decode(Int.self, forKey: .logPosition, orDefault: logPosition)
		emittedAt = try box.decode(String.self, forKey: .emittedAt, orDefault: emittedAt)
	}
}
