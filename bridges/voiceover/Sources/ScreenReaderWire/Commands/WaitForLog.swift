// ROLE: entity -- `waitForLog`'s params and result.
//
// Pure. `found == false` on timeout is a normal answer, as with every wait in
// this contract; `position` is where to resume reading either way, so a failed
// wait still tells the caller where it got to.

public struct WaitForLogParams: Codable, Equatable, Sendable {
	public var timeout: Double = 5.0
	public var minLevel: LogLevel?
	public var contains: [String]?

	public init(timeout: Double = 5.0, minLevel: LogLevel? = nil, contains: [String]? = nil) {
		self.timeout = timeout
		self.minLevel = minLevel
		self.contains = contains
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		timeout = try box.decode(Double.self, forKey: .timeout, orDefault: timeout)
		minLevel = try box.decodeIfPresent(LogLevel.self, forKey: .minLevel)
		contains = try box.decodeIfPresent([String].self, forKey: .contains)
	}
}

public struct WaitForLogResult: Codable, Equatable, Sendable {
	public var found: Bool
	public var position: Int
	public var text: String = ""

	public init(found: Bool, position: Int, text: String = "") {
		self.found = found
		self.position = position
		self.text = text
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		found = try box.decode(Bool.self, forKey: .found)
		position = try box.decode(Int.self, forKey: .position)
		text = try box.decode(String.self, forKey: .text, orDefault: text)
	}
}
