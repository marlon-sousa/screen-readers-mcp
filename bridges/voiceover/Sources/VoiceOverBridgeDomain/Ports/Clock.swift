// ROLE: port -- what the domain needs from the world about time.
//
// IMPLEMENTED BY: RealClock (adapters, a leaf) and FakeClock (Tests/Fakes).
// USED BY: the Session's two watchdogs, and every wait loop a later entry adds.
//
// TIME IS INJECTED, NEVER PATCHED. FakeClock.sleep is an instant advance, so a
// 30-second heartbeat test runs in microseconds; a library that swizzles the
// global clock would leave the real sleep in place and make this port pointless.
//
// TWO CLOCKS, ONE PORT, because they answer different questions. `monotonic` is
// the only one a deadline may be measured with -- it cannot go backwards when
// the machine's clock is corrected. `now` is wall-clock epoch seconds, and it
// exists because a captured utterance's timestamp has to line up with things
// stamped elsewhere (spec 0028); a duration measured with it would be a bug.
public protocol Clock: AnyObject {
	/// Seconds from an arbitrary fixed origin; only differences mean anything.
	func monotonic() -> Double

	/// Block for `seconds`. A fake makes this an instant advance.
	func sleep(_ seconds: Double)

	/// Wall-clock epoch seconds, comparable with a timestamp recorded elsewhere.
	func now() -> Double
}
