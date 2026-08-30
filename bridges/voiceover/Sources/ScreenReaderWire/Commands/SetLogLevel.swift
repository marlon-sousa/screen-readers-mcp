// ROLE: entity -- `setLogLevel`'s params and result.
//
// Pure. The result reports the PREVIOUS level as well as the new one, because
// the session is obliged to put it back at teardown and a caller that changed it
// twice would otherwise have to remember what it started from.

public struct SetLogLevelParams: Codable, Equatable, Sendable {
	public var level: LogLevel

	public init(level: LogLevel) {
		self.level = level
	}
}

public struct LogLevelResult: Codable, Equatable, Sendable {
	public var level: LogLevel
	public var previous: LogLevel

	public init(level: LogLevel, previous: LogLevel) {
		self.level = level
		self.previous = previous
	}
}
