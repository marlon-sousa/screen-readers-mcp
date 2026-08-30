// A hand-written stateful fake for the PublishedVoices adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/PublishedVoices.swift.
//
// A list, and nothing else. What matters in the tests above it is that the
// published identifier is NOT the one the audio unit declared -- the system
// prefixes it -- so the default here carries that prefix, and a suffix match is
// the only thing that finds it.

@testable import VoiceOverBridgeAdapters

public final class FakePublishedVoices: PublishedVoices {
	public var voices: [String]

	public init(voices: [String] = []) {
		self.voices = voices
	}

	public func identifiers() -> [String] { voices }
}
