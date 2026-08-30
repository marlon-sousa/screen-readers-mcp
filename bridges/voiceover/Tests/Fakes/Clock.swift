// A hand-written stateful fake for the Clock port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/Clock.swift.
//
// SLEEP IS AN INSTANT ADVANCE, which is the whole reason time is a port here: a
// 30-second heartbeat test runs in microseconds and asserts on the same code
// paths a real one would. A library that swizzled the global clock would leave
// the real sleep in place and the test would take thirty seconds.

import VoiceOverBridgeDomain

public final class FakeClock: Clock {
	private var monotonicSeconds: Double
	private var epochSeconds: Double

	/// Every sleep, in order, so a test can assert on how long something waited
	/// as well as on what it did afterwards.
	public private(set) var sleeps: [Double] = []

	public init(monotonic: Double = 1000.0, epoch: Double = 1_700_000_000.0) {
		self.monotonicSeconds = monotonic
		self.epochSeconds = epoch
	}

	public func monotonic() -> Double { monotonicSeconds }

	public func now() -> Double { epochSeconds }

	/// Records the request and advances instead of waiting.
	public func sleep(_ seconds: Double) {
		sleeps.append(seconds)
		advance(seconds)
	}

	/// Move both clocks on. Both, because a test that advanced only one would be
	/// asserting against a machine whose wall clock had stopped.
	public func advance(_ seconds: Double) {
		monotonicSeconds += seconds
		epochSeconds += seconds
	}
}
