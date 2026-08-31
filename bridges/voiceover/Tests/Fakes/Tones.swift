// A hand-written stateful fake for the Tones adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/Tones.swift.
//
// NO TEST MAY MAKE A SOUND. It records the frequencies asked for, which is what
// makes the one thing AudibleSessionSignals decides assertable: that taking
// control RISES and releasing it FALLS, so a listener has one thing to learn
// rather than four.

import VoiceOverBridgeAdapters

public final class FakeTones: Tones {
	public struct ToneFailed: Error {
		public init() {}
	}

	public private(set) var played: [[Double]] = []
	/// The rhythm each call asked for. Recorded since 13.11, because the cue's
	/// LENGTH and SPACING turned out to be as much of what a listener hears as its
	/// pitches -- a pair played back to back is one sound that changes pitch, and
	/// the point of a pair is that it is two beeps.
	public private(set) var rhythms: [(seconds: Double, gap: Double)] = []
	public var fails = false

	public init() {}

	public func play(_ frequencies: [Double], seconds: Double, gapSeconds: Double) throws {
		played.append(frequencies)
		rhythms.append((seconds: seconds, gap: gapSeconds))
		if fails { throw ToneFailed() }
	}
}
