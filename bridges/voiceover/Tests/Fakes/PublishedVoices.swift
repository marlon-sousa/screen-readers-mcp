// Hand-written stateful fake for the PublishedVoices adapter seam.

@testable import VoiceOverBridgeAdapters

public final class FakePublishedVoices: PublishedVoices {
	public var voices: [String]

	public init(voices: [String] = []) {
		self.voices = voices
	}

	public private(set) var enumerations = 0

	public func identifiers() -> [String] {
		enumerations += 1
		return voices
	}

	public private(set) var refreshes = 0

	public var onRefresh: (() -> Void)?

	public func refresh() {
		refreshes += 1
		onRefresh?()
	}
}
