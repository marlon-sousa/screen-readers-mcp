// Mirrors Sources/VoiceOverBridgeAdapters/AudibleSessionSignals.swift.

import Fakes
import Testing
import VoiceOverBridgeDomain

@testable import VoiceOverBridgeAdapters

@Suite("AudibleSessionSignals")
struct AudibleSessionSignalsTests {
	private func signals(
		tones: FakeTones = FakeTones(),
		announcer: FakeAnnouncer = FakeAnnouncer(),
		config: FakeBridgeConfig = FakeBridgeConfig()
	) -> AudibleSessionSignals {
		AudibleSessionSignals(tones: tones, announcer: announcer, config: config)
	}

	@Test("TAKING CONTROL RISES AND RELEASING IT FALLS")
	func theTonesAreOpposites() throws {
		let tones = FakeTones()
		let subject = signals(tones: tones)
		try subject.sessionStarted(persona: "")
		try subject.sessionEnded()
		#expect(tones.played.count == 2)
		let taken = try #require(tones.played.first)
		let released = try #require(tones.played.last)
		#expect(taken == taken.sorted())
		#expect(released == released.sorted().reversed())
		#expect(taken == released.reversed())
	}

	@Test("the start cue SAYS what the session is standing in for")
	func theStartCueNamesThePersona() throws {
		let announcer = FakeAnnouncer()
		try signals(announcer: announcer).sessionStarted(persona: "blind first-time user")
		#expect(announcer.spoken.count == 1)
		#expect(announcer.spoken[0].contains("blind first-time user"))
	}

	@Test("a session with no declared persona still says that one started")
	func noPersonaIsStillAnnounced() throws {
		let announcer = FakeAnnouncer()
		try signals(announcer: announcer).sessionStarted(persona: "  ")
		#expect(announcer.spoken == ["screen reader testing session started"])
	}

	@Test("ending says nothing: two descending tones are all there is to say")
	func endingIsToneOnly() throws {
		let announcer = FakeAnnouncer()
		try signals(announcer: announcer).sessionEnded()
		#expect(announcer.spoken.isEmpty)
	}

	@Test("the silence-cap WARNING is spoken, because a tone cannot say what is about to happen")
	func theWarningIsSpoken() throws {
		let announcer = FakeAnnouncer()
		let tones = FakeTones()
		try signals(tones: tones, announcer: announcer).silenceWarning()
		#expect(tones.played.count == 1)
		#expect(announcer.spoken.count == 1)
	}

	@Test("the LIFT is marked audibly, which is what §6.1 asks for")
	func theLiftIsMarked() throws {
		let tones = FakeTones()
		try signals(tones: tones).silenceLifted()
		#expect(tones.played.count == 1)
	}

	@Test("THE RE-ARM IS THE LIFT'S CUE PLAYED BACKWARDS, and it carries words")
	func theReArmIsMarkedAndSpoken() throws {
		let tones = FakeTones()
		let announcer = FakeAnnouncer()
		try signals(tones: tones, announcer: announcer).silenceResuppressed()
		#expect(tones.played.count == 1)
		#expect(tones.played.first == AudibleSessionSignals.Cue.lifted.reversed())
		#expect(announcer.spoken.count == 1)
	}

	@Test("CUES OFF MEANS SILENT, and it is read on every cue rather than at construction")
	func theSwitchIsHonouredLive() throws {
		let tones = FakeTones()
		let announcer = FakeAnnouncer()
		let config = FakeBridgeConfig()
		let subject = signals(tones: tones, announcer: announcer, config: config)
		try subject.sessionStarted(persona: "someone")
		config.cuesEnabled = false
		try subject.sessionEnded()
		try subject.silenceWarning()
		try subject.silenceLifted()
		try subject.silenceResuppressed()
		#expect(tones.played.count == 1)
		#expect(announcer.spoken.count == 1)
	}

	@Test("a cue that fails throws, because the session is what guards it")
	func aFailureReachesTheSession() {
		let tones = FakeTones()
		tones.fails = true
		#expect(throws: FakeTones.ToneFailed.self) { try signals(tones: tones).sessionEnded() }
	}

	@Test("a cue is TWO beeps, at lane 1's own rhythm, not one sound that changes pitch")
	func theCueRhythmMatchesLaneOne() throws {
		let tones = FakeTones()
		let signals = AudibleSessionSignals(
			tones: tones, announcer: FakeAnnouncer(), config: FakeBridgeConfig())
		try signals.sessionStarted(persona: "user")

		let rhythm = try #require(tones.rhythms.first)
		#expect(rhythm.seconds == 0.18)
		#expect(rhythm.gap == 0.12)
		#expect(rhythm.seconds + rhythm.gap == 0.30)
	}

}
