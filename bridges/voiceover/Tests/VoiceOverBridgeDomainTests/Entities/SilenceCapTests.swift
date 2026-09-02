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

	@Test("A LIFTED SESSION GOES QUIET AGAIN once the human has heard their machine")
	func aLiftedSessionReArms() {
		// THE DEFECT THIS EXISTS FOR, reported by Marlon on 2026-09-01 while
		// driving the bridge: connect, stay quiet, get warned, stay quiet, get
		// lifted, then announce -- and the machine never went silent again.
		// `didLift` was a one-way latch and `check` answered `.none` forever after.
		// protocol.md §6.1 rule 4 says a lifted session MAY go quiet again on a
		// fresh window; a lift is a bounded window ending, not a decision that this
		// session is finished being silent.
		let subject = cap()
		#expect(subject.check(1090) == SilenceCapAction.lift)
		#expect(subject.lifted)
		// Still nothing owed: the human has been told nothing since.
		#expect(subject.check(1150) == SilenceCapAction.none)
		subject.heard(1160)
		#expect(subject.check(1161) == SilenceCapAction.resuppress)
		#expect(!subject.lifted)
	}

	@Test("nothing HEARD, nothing re-armed: a timer must not mute somebody who was told nothing")
	func silenceAloneNeverReArms() {
		// The lift ends a window because the human has been mute for too long.
		// Re-arming on the clock alone would take their machine away again for the
		// very reason it was given back, which is the harm rather than the fix.
		let subject = cap()
		_ = subject.check(1090)
		for instant in stride(from: 1100.0, through: 1400.0, by: 25.0) {
			#expect(subject.check(instant) == SilenceCapAction.none)
		}
	}

	@Test("the fresh window is a FULL one, measured from the moment it goes quiet")
	func theFreshWindowIsFullLength() {
		// "On a fresh window of the same length" (§6.1 rule 4). It starts at the
		// re-arm and not at the announcement: the human could hear everything up to
		// that instant, so charging the new window for it would shorten it.
		let subject = cap()
		_ = subject.check(1090)
		subject.heard(1100)
		#expect(subject.check(1200) == SilenceCapAction.resuppress)
		#expect(subject.check(1244) == SilenceCapAction.none)
		#expect(subject.check(1245) == SilenceCapAction.warn)
		#expect(subject.check(1290) == SilenceCapAction.lift)
	}

	@Test("EXPOSURE STAYS BOUNDED across any number of re-arms")
	func exposureIsBoundedAcrossReArms() {
		// The rule's own reason for existing: an agent must not be able to
		// accumulate unbounded silence out of bounded pieces. Every piece is
		// bounded and every boundary is heard.
		let subject = cap()
		var now = 1000.0
		for _ in 0..<5 {
			now += 90
			#expect(subject.check(now) == SilenceCapAction.lift)
			subject.heard(now + 1)
			now += 2
			#expect(subject.check(now) == SilenceCapAction.resuppress)
		}
	}

	@Test("one re-arm per hearing: a narrating agent does not re-arm on every tick")
	func theReArmIsOwedOnce() {
		let subject = cap()
		_ = subject.check(1090)
		subject.heard(1100)
		#expect(subject.check(1101) == SilenceCapAction.resuppress)
		#expect(subject.check(1102) == SilenceCapAction.none)
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
