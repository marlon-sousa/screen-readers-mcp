// ROLE: entity, `announce`'s params; it answers with the shared AckResult.

public struct AnnounceParams: Codable, Equatable, Sendable {
	public var text: String

	public init(text: String) {
		self.text = text
	}
}
