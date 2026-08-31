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

	/// How many times the machine's list was actually asked for. It matters to one
	/// caller: `SynthesizerAnnouncer` resolves its voice ONCE and keeps it, because
	/// the list is a property of the machine and an announcement in a different
	/// voice each time is worse to listen to than one in the wrong voice.
	public private(set) var enumerations = 0

	public func identifiers() -> [String] {
		enumerations += 1
		return voices
	}
}
