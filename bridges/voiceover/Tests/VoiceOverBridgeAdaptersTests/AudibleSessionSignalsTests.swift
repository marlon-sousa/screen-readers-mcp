// Mirrors Sources/VoiceOverBridgeAdapters/AudibleSessionSignals.swift.
//
// THREE PROPERTIES, AND EACH IS ABOUT THE PERSON AT THE MACHINE:
//
//  1. TAKING CONTROL RISES AND RELEASING IT FALLS. That is the whole of what a
//     listener has to learn, and two pairs that were not each other's opposite
//     would be four sounds to memorise instead.
//  2. THE START CUE CARRIES WORDS. Tones cannot say what a session is standing in
//     for, and the person sitting there deserves to know which (spec 0029).
//  3. THE SWITCH IS READ ON EVERY CUE, so a human who turns the cues off while a
//     session is running means now.
//
// NO TEST HERE MAKES A SOUND OR SPEAKS: both seams are fakes.

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
		// protocol.md §6.1 asks for a warning to the human, and "your machine is
		// about to speak again" is not a thing two tones can convey.
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
		// Only the first cue was made: a human who silences the cues mid-session
		// means now, not next time.
		#expect(tones.played.count == 1)
		#expect(announcer.spoken.count == 1)
	}

	@Test("a cue that fails throws, because the session is what guards it")
	func aFailureReachesTheSession() {
		// A courtesy is never worth a session (see SessionSignals), and the Session
		// guards exactly the calls that can fail -- so this must be one of them.
		let tones = FakeTones()
		tones.fails = true
		#expect(throws: FakeTones.ToneFailed.self) { try signals(tones: tones).sessionEnded() }
	}
}
