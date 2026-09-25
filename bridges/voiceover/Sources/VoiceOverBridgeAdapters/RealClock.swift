// ROLE: leaf adapter implementing the Clock port with the system clock.
// BUILT BY: Wiring.

import Foundation
import VoiceOverBridgeDomain

public final class RealClock: Clock {
	public init() {}

	/// Monotonic, so a deadline cannot move when the wall clock is corrected.
	public func monotonic() -> Double {
		ProcessInfo.processInfo.systemUptime
	}

	public func sleep(_ seconds: Double) {
		Thread.sleep(forTimeInterval: seconds)
	}

	public func now() -> Double {
		Date().timeIntervalSince1970
	}
}
