// ROLE: port -- what the domain needs from the world about time.
// IMPLEMENTED BY: RealClock and FakeClock.
// USED BY: the Session's watchdogs and every wait loop.
// A deadline is measured only with `monotonic`; `now` is wall-clock epoch seconds, for timestamps only.
public protocol Clock: AnyObject {
	func monotonic() -> Double

	func sleep(_ seconds: Double)

	func now() -> Double
}
