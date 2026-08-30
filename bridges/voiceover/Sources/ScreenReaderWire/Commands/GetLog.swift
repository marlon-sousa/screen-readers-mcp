// ROLE: entity -- `getLog`'s params and result.
//
// Pure. Not implemented by this bridge -- VoiceOver emits no diagnostic log of
// its own (52 unified-log records in a measured hour, every one from a framework
// it links; spec 0046 part 2), so `log` is not in its capability set. The shape
// is bound anyway, for the reason in Command.swift's header.
//
// EVERY FILTER IS OPTIONAL AND THE BOUNDS ARE NOT: `maxEntries` defaults to 200
// and `windows` to 1, because a log slice that were unbounded by default would
// be incomplete by default -- an agent would read a truncated answer believing
// it had the whole thing (protocol.md §5).

public struct GetLogParams: Codable, Equatable, Sendable {
	/// The command anchor: which request's window to read. nil means the most
	/// recently marked command.
	public var commandId: Int?
	public var windows: Int = 1
	public var sincePosition: Int?
	public var lastSeconds: Double?
	public var minLevel: LogLevel?
	public var contains: [String]?
	public var exclude: [String]?
	/// Which fields of each entry to render; nil means the reader's own default
	/// selection (time, level, module, message).
	public var fields: [String]?
	public var maxEntries: Int = 200

	public init(
		commandId: Int? = nil,
		windows: Int = 1,
		sincePosition: Int? = nil,
		lastSeconds: Double? = nil,
		minLevel: LogLevel? = nil,
		contains: [String]? = nil,
		exclude: [String]? = nil,
		fields: [String]? = nil,
		maxEntries: Int = 200
	) {
		self.commandId = commandId
		self.windows = windows
		self.sincePosition = sincePosition
		self.lastSeconds = lastSeconds
		self.minLevel = minLevel
		self.contains = contains
		self.exclude = exclude
		self.fields = fields
		self.maxEntries = maxEntries
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		commandId = try box.decodeIfPresent(Int.self, forKey: .commandId)
		windows = try box.decode(Int.self, forKey: .windows, orDefault: windows)
		sincePosition = try box.decodeIfPresent(Int.self, forKey: .sincePosition)
		lastSeconds = try box.decodeIfPresent(Double.self, forKey: .lastSeconds)
		minLevel = try box.decodeIfPresent(LogLevel.self, forKey: .minLevel)
		contains = try box.decodeIfPresent([String].self, forKey: .contains)
		exclude = try box.decodeIfPresent([String].self, forKey: .exclude)
		fields = try box.decodeIfPresent([String].self, forKey: .fields)
		maxEntries = try box.decode(Int.self, forKey: .maxEntries, orDefault: maxEntries)
	}
}

public struct LogSliceResult: Codable, Equatable, Sendable {
	public var text: String
	/// How many entries this slice carries, and how many matched before the
	/// bound was applied -- so `truncated` is never the only warning.
	public var entries: Int
	public var matched: Int
	public var truncated: Bool
	public var nextPosition: Int
	/// The verbosity the log was CAPTURED at, which bounds what any filter here
	/// could have found.
	public var capturedAtLevel: LogLevel
	public var fromCommandId: Int?
	public var toCommandId: Int?

	public init(
		text: String,
		entries: Int,
		matched: Int,
		truncated: Bool,
		nextPosition: Int,
		capturedAtLevel: LogLevel,
		fromCommandId: Int? = nil,
		toCommandId: Int? = nil
	) {
		self.text = text
		self.entries = entries
		self.matched = matched
		self.truncated = truncated
		self.nextPosition = nextPosition
		self.capturedAtLevel = capturedAtLevel
		self.fromCommandId = fromCommandId
		self.toCommandId = toCommandId
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		text = try box.decode(String.self, forKey: .text)
		entries = try box.decode(Int.self, forKey: .entries)
		matched = try box.decode(Int.self, forKey: .matched)
		truncated = try box.decode(Bool.self, forKey: .truncated)
		nextPosition = try box.decode(Int.self, forKey: .nextPosition)
		capturedAtLevel = try box.decode(LogLevel.self, forKey: .capturedAtLevel)
		fromCommandId = try box.decodeIfPresent(Int.self, forKey: .fromCommandId)
		toCommandId = try box.decodeIfPresent(Int.self, forKey: .toCommandId)
	}
}
