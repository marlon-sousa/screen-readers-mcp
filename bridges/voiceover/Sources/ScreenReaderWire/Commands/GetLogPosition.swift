// ROLE: entity -- `getLogPosition`'s result. The command has no params.
//
// Pure. The position is a coordinate a later `getLog` reads from, so a session
// marks its place before acting exactly as it does with speech indices. `time`
// is the same instant in ISO 8601, for the human reading a transcript.

public struct LogPositionResult: Codable, Equatable, Sendable {
	public var position: Int
	public var time: String

	public init(position: Int, time: String) {
		self.position = position
		self.time = time
	}
}
