// ROLE: entity -- `announce`'s params. It answers with the shared AckResult.
//
// Pure. This is the `interact` capability's first half: a session speaking TO
// the human at the machine, which is the only channel it has when the reader is
// silenced for capture. It is why a silent session is not a session with nobody
// home.

public struct AnnounceParams: Codable, Equatable, Sendable {
	public var text: String

	public init(text: String) {
		self.text = text
	}
}
