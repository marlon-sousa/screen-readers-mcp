// Mirrors Sources/VoiceOverBridgeDomain/Entities/SilenceCap.swift.
//
// Plain numbers, no clock and no doubles: the entity takes `now` as an argument
// precisely so the watchdog that decides when a blind person gets their machine
// back is testable without waiting ninety seconds for it.

import Testing

@testable import VoiceOverBridgeDomain

@Suite("SilenceCap")
struct SilenceCapTests {
	private func cap(
		enabled: Bool = true, warn: Double = 45, lift: Double = 90, at start: Double = 1000
	) -> SilenceCap {
		SilenceCap(policy: SilenceCapPolicy(enabled: enabled, warnAfter: warn, liftAfter: lift), now: start)
	}

	@Test("a young window owes nothing")
	func nothingOwedEarly() {
		#expect(cap().check(1040) == SilenceCapAction.none)
	}

	@Test("the warning is owed once the warn threshold passes, and ONLY ONCE")
	func warnsOnce() {
		let subject = cap()
		#expect(subject.check(1045) == SilenceCapAction.warn)
		#expect(subject.check(1046) == SilenceCapAction.none)
		#expect(subject.check(1080) == SilenceCapAction.none)
	}

	@Test("the lift is owed at the lift threshold, and only once")
	func liftsOnce() {
		let subject = cap()
		_ = subject.check(1045)
		#expect(subject.check(1090) == SilenceCapAction.lift)
		#expect(subject.lifted)
		#expect(subject.check(1200) == SilenceCapAction.none)
	}

	@Test("STARVED PAST BOTH AT ONCE, the machine is given back rather than warned about")
	func liftBeatsWarn() {
		// The lift is the guarantee and the warning is a courtesy. A loop that was
		// blocked past both thresholds must not spend its turn warning about a
		// silence that has already run past its limit.
		#expect(cap().check(1200) == SilenceCapAction.lift)
	}

	@Test("hearing the machine starts a fresh window, and re-arms the warning")
	func hearingResets() {
		let subject = cap()
		#expect(subject.check(1045) == SilenceCapAction.warn)
		subject.heard(1050)
		#expect(subject.check(1090) == SilenceCapAction.none)
		#expect(subject.check(1095) == SilenceCapAction.warn)
	}

	@Test("an unattended machine is never capped: un-muting an empty room is damage")
	func unattendedNeverFires() {
		let subject = cap(enabled: false)
		#expect(subject.check(100_000) == SilenceCapAction.none)
		#expect(subject.lifted == false)
	}

	@Test("an unordered pair falls back to the SHIPPED thresholds, never to no cap")
	func unorderedFallsBackToDefaults() {
		// Two settings read independently can each look sane and still cross over,
		// and "warn after the lift" means the warning is never spoken while nothing
		// looks wrong. Failing toward the defaults is the same safe direction the
		// whole entry takes.
		let policy = SilenceCapPolicy(enabled: true, warnAfter: 120, liftAfter: 30)
		#expect(policy.warnAfter == defaultWarnAfter)
		#expect(policy.liftAfter == defaultLiftAfter)
		#expect(policy.enabled)
	}

	@Test("a zero or negative warning is not a cap that fires instantly, it is the default")
	func nonPositiveWarnFallsBack() {
		#expect(SilenceCapPolicy(enabled: true, warnAfter: 0, liftAfter: 90).warnAfter == defaultWarnAfter)
		#expect(SilenceCapPolicy(enabled: true, warnAfter: -1, liftAfter: 90).liftAfter == defaultLiftAfter)
	}

	@Test("the unconfigured machine is CAPPED, on the shipped numbers")
	func theDefaultIsCapped() {
		// A machine nobody has configured is not a machine we may assume is empty.
		#expect(SilenceCapPolicy.attendedDefault.enabled)
		#expect(SilenceCapPolicy.attendedDefault.warnAfter == 45)
		#expect(SilenceCapPolicy.attendedDefault.liftAfter == 90)
	}
}
