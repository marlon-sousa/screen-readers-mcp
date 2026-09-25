import VoiceOverBridgeDomain

public final class FakeAnnouncer: Announcer {
	public struct SpeechFailed: Error {
		public init() {}
	}

	public private(set) var spoken: [String] = []

	/// Throws after recording the attempt.
	public var fails = false

	public init() {}

	public func announce(_ text: String) throws {
		spoken.append(text)
		if fails { throw SpeechFailed() }
	}
}
