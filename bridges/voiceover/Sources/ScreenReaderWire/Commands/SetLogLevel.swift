// ROLE: entity, `setLogLevel`'s params and result.

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
