import VoiceOverBridgeDomain

public final class FakeClock: Clock {
	private var monotonicSeconds: Double
	private var epochSeconds: Double

	public private(set) var sleeps: [Double] = []

	public init(monotonic: Double = 1000.0, epoch: Double = 1_700_000_000.0) {
		self.monotonicSeconds = monotonic
		self.epochSeconds = epoch
	}

	public func monotonic() -> Double { monotonicSeconds }

	public func now() -> Double { epochSeconds }

	public func sleep(_ seconds: Double) {
		sleeps.append(seconds)
		advance(seconds)
	}

	/// Both clocks move, or the wall clock would appear stopped.
	public func advance(_ seconds: Double) {
		monotonicSeconds += seconds
		epochSeconds += seconds
	}
}
