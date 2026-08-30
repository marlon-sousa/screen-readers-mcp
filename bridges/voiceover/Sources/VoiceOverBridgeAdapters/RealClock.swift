// ROLE: LEAF adapter -- IMPLEMENTS the Clock domain port with the system clock.
//
// BUILT BY: Wiring.
//
// NO TEST FILE, and that is a statement: nothing here makes a decision. The code
// that reasons about time -- deadlines, wait loops -- lives in the domain and is
// tested against FakeClock, whose sleep is an instant advance. A test here would
// assert that the operating system can tell the time.

import Foundation
import VoiceOverBridgeDomain

public final class RealClock: Clock {
	public init() {}

	/// Monotonic, so a deadline cannot be moved by the machine's clock being
	/// corrected. `ProcessInfo.systemUptime` is CLOCK_MONOTONIC's Foundation
	/// spelling; unlike Date it does not go backwards.
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
