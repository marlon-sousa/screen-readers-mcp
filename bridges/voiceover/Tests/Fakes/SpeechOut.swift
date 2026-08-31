// A hand-written stateful fake for the SpeechOut adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/SpeechOut.swift.
//
// NO TEST MAY SPEAK. This is what SynthesizerAnnouncer is exercised against, and
// it records the VOICE as well as the words -- because the one decision that
// adapter makes is which voice, and the one way it could fail silently is by
// choosing our own capture voice, which renders nothing while a silent session
// holds the marker.

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
