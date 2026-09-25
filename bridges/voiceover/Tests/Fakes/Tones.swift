// Hand-written stateful fake for the Tones adapter seam; no test may make a sound.

import VoiceOverBridgeAdapters

public final class FakeTones: Tones {
	public struct ToneFailed: Error {
		public init() {}
	}

	public private(set) var played: [[Double]] = []
	public private(set) var rhythms: [(seconds: Double, gap: Double)] = []
	public var fails = false

	public init() {}

	public func play(_ frequencies: [Double], seconds: Double, gapSeconds: Double) throws {
		played.append(frequencies)
		rhythms.append((seconds: seconds, gap: gapSeconds))
		if fails { throw ToneFailed() }
	}
}
