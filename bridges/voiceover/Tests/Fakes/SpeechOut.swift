// Hand-written stateful fake for the SpeechOut adapter seam; no test may speak.

import VoiceOverBridgeAdapters

public final class FakeSpeechOut: SpeechOut {
	public struct SpeechFailed: Error {
		public init() {}
	}

	public private(set) var spoken: [(text: String, voice: String?)] = []
	public var fails = false

	public init() {}

	public func speak(_ text: String, voiceIdentifier: String?) throws {
		spoken.append((text, voiceIdentifier))
		if fails { throw SpeechFailed() }
	}
}
