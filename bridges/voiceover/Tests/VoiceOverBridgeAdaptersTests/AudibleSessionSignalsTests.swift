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

	@Test("THE RE-ARM IS THE LIFT'S CUE PLAYED BACKWARDS, and it carries words")
	func theReArmIsMarkedAndSpoken() throws {
		// §6.1 rule 4 asks for each re-suppression to be audibly marked, and this
		// is the cue whose absence is worst: the machine is being taken away from
		// the human a second time, and two tones cannot say why their reader has
		// just gone quiet. The pair is the lift's, reversed -- one shape to learn,
		// and which way it runs says which of the two just happened.
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

	@Test("a cue is TWO beeps, at lane 1's own rhythm, not one sound that changes pitch")
	func theCueRhythmMatchesLaneOne() throws {
		// The property is that a listener can COUNT the beeps. Two tones played
		// back to back are heard as one sound changing pitch halfway, which is what
		// this bridge did until 13.11 and what the maintainer -- who uses the NVDA
		// bridge daily -- described as "light" beside lane 1's "clear".
		//
		// The numbers are lane 1's, from nvda_session_signals.py: _TONE_MS = 180
		// and _GAP_MS = 300 start-to-start, so 180 ms of tone and 120 ms of silence.
		// Asserted rather than left to a constant, because the whole defect was a
		// constant nobody had argued for.
		let tones = FakeTones()
		let signals = AudibleSessionSignals(
			tones: tones, announcer: FakeAnnouncer(), config: FakeBridgeConfig())
		try signals.sessionStarted(persona: "user")

		let rhythm = try #require(tones.rhythms.first)
		#expect(rhythm.seconds == 0.18)
		#expect(rhythm.gap == 0.12)
		// 300 ms start to start, which is what makes the pair countable.
		#expect(rhythm.seconds + rhythm.gap == 0.30)
	}

}
