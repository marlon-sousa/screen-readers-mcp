// ROLE: entity, `getLogPosition`'s result; the command has no params.

public struct LogPositionResult: Codable, Equatable, Sendable {
	public var position: Int
	public var time: String

	public init(position: Int, time: String) {
		self.position = position
		self.time = time
	}
}
