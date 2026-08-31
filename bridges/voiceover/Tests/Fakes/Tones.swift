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
	public var fails = false

	public init() {}

	public func play(_ frequencies: [Double], seconds: Double) throws {
		played.append(frequencies)
		if fails { throw ToneFailed() }
	}
}
