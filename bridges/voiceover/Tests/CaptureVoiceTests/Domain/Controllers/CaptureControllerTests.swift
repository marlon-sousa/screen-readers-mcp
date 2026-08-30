// Mirrors Sources/CaptureVoice/Domain/Controllers/CaptureController.swift.
//
// The whole point of the decomposition: this runs headlessly, with no audio
// device, no extension and no VoiceOver. Every assertion here was a comment in
// the spike's one audio-unit class, provable only by pointing the maintainer's
// only screen reader at an untested voice.

import Testing

@testable import CaptureVoice

@Suite("CaptureController")
struct CaptureControllerTests {
	static let ourSuffix = "org.screen-readers-mcp.spike.capture"
	static let ours = AvailableVoice(
		identifier: "ext." + ourSuffix, name: "Capture Spike", language: "pt-BR")
	static let brazilian = AvailableVoice(
		identifier: "com.apple.voice.compact.pt-BR.Luciana", name: "Luciana", language: "pt-BR")
	static let arabic = AvailableVoice(
		identifier: "com.apple.voice.compact.ar-001.Maged", name: "Maged", language: "ar-001")

	/// A builder rather than a fixture: every test varies the mode, the catalogue
	/// or what the synthesizer reports, which is the case AGENTS.md names as a
	/// builder's and not a fixture's.
	struct Subject {
		let controller: CaptureController
		let sink: FakeUtteranceSink
		let synthesizer: FakeSynthesizer
		let catalogue: FakeVoiceCatalogue
		let mode: FakeCaptureModeSource
		let ring: AudioRing
	}

	func makeSubject(
		silent: Bool = false,
		preferredVoice: String? = nil,
		currentLanguage: String = "pt-BR",
		defaults: [String: AvailableVoice] = ["pt-BR": brazilian],
		voices: [AvailableVoice] = [arabic, brazilian, ours]
	) -> Subject {
		let sink = FakeUtteranceSink()
		let synthesizer = FakeSynthesizer()
		let catalogue = FakeVoiceCatalogue(
			currentLanguage: currentLanguage, defaults: defaults, voices: voices)
		let mode = FakeCaptureModeSource(silent: silent, preferredVoice: preferredVoice)
		let ring = AudioRing(capacity: 1024)
		return Subject(
			controller: CaptureController(
				sink: sink,
				synthesizer: synthesizer,
				catalogue: catalogue,
				mode: mode,
				ring: ring,
				ourVoiceIdentifier: CaptureControllerTests.ourSuffix
			),
			sink: sink,
			synthesizer: synthesizer,
			catalogue: catalogue,
			mode: mode,
			ring: ring
		)
	}

	// -- the text half, which happens whatever the audio half does ------------

	@Test("silent: the text still goes out, and no audio is produced")
	func silentEmitsTextAndNoAudio() {
		let subject = makeSubject(silent: true)
		subject.controller.capture(ssml: "<speak>um dois</speak>", requestedBy: "ours")

		#expect(subject.sink.events(ofKind: .synthesize).count == 1)
		#expect(subject.sink.field("text", ofKind: .synthesize) == .text("um dois"))
		#expect(subject.sink.field("silent", ofKind: .synthesize) == .flag(true))
		#expect(subject.synthesizer.spoken.isEmpty)
		// Closed rather than left open, so the render block reports the utterance
		// complete instead of waiting for samples that will never come.
		#expect(subject.ring.isFinished)
	}

	@Test("not silent: the text goes out AND the audio is started")
	func nonSilentEmitsBoth() {
		let subject = makeSubject()
		subject.controller.capture(ssml: "<speak>um dois</speak>", requestedBy: "ours")

		#expect(subject.sink.field("text", ofKind: .synthesize) == .text("um dois"))
		#expect(subject.sink.field("silent", ofKind: .synthesize) == .flag(false))
		#expect(subject.synthesizer.spoken.count == 1)
		// Into the controller's OWN ring -- the one the render block drains.
		#expect(subject.synthesizer.ringsSpokenInto.first === subject.ring)
	}

	@Test("the text is emitted BEFORE synthesis starts, so it never waits on audio")
	func textDoesNotWaitForAudio() {
		let subject = makeSubject()
		var eventsWhenSpeakBegan = -1
		subject.synthesizer.onSpeak = { eventsWhenSpeakBegan = subject.sink.events.count }
		subject.controller.capture(ssml: "<speak>um</speak>", requestedBy: "ours")
		#expect(eventsWhenSpeakBegan == 1)
	}

	@Test("the raw SSML is passed through untouched, prosody and all")
	func rawSsmlSurvives() {
		let ssml = "<speak><prosody rate=\"160%\">Data</prosody></speak>"
		let subject = makeSubject()
		subject.controller.capture(ssml: ssml, requestedBy: "ours")
		#expect(subject.sink.field("ssml", ofKind: .synthesize) == .text(ssml))
	}

	@Test("the requesting voice is reported as asked for, not as re-spoken")
	func theRequestingVoiceIsRecorded() {
		let subject = makeSubject()
		subject.controller.capture(ssml: "<speak>um</speak>", requestedBy: "ext.ours")
		#expect(subject.sink.field("voice", ofKind: .synthesize) == .text("ext.ours"))
		#expect(subject.sink.field("passthrough_voice", ofKind: .synthesize)
			== .text(CaptureControllerTests.brazilian.identifier))
	}

	@Test("sequence numbers count up, so two identical utterances are two events")
	func sequenceNumbersDistinguishRepeats() {
		// Six of 62 measured utterances were byte-identical to the one before.
		// Polling cannot tell those from silence; this can.
		let subject = makeSubject()
		subject.controller.capture(ssml: "<speak>um</speak>", requestedBy: "ours")
		subject.controller.capture(ssml: "<speak>um</speak>", requestedBy: "ours")
		let sequences = subject.sink.events(ofKind: .synthesize).map { $0.fields["seq"] }
		#expect(sequences == [.count(1), .count(2)])
	}

	@Test("the mode is asked ONCE PER UTTERANCE, never cached")
	func silenceIsReReadEveryTime() {
		// The bridge lifts silence between two utterances and the lift has to take
		// effect on the next one.
		let subject = makeSubject(silent: true)
		subject.controller.capture(ssml: "<speak>um</speak>", requestedBy: "ours")
		subject.mode.silent = false
		subject.controller.capture(ssml: "<speak>dois</speak>", requestedBy: "ours")
		#expect(subject.mode.reads == 2)
		#expect(subject.synthesizer.spoken.count == 1)
	}

	// -- the choice, end to end through the ports -----------------------------

	@Test("with no language in the SSML the SYSTEM's language decides")
	func systemLanguageDecidesWhenSsmlIsSilent() {
		let subject = makeSubject()
		subject.controller.capture(ssml: "<speak>Data de Modificação</speak>", requestedBy: "ours")
		#expect(subject.catalogue.defaultLookups == ["pt-BR"])
		#expect(subject.synthesizer.spoken.first?.voice == CaptureControllerTests.brazilian)
		#expect(subject.sink.field("utterance_language", ofKind: .synthesize) == .text("<unknown>"))
		#expect(subject.sink.field("passthrough_language", ofKind: .synthesize) == .text("pt-BR"))
	}

	@Test("the full voice list is NOT enumerated when the language's default already wins")
	func theCommonPathDoesNotEnumerateEveryVoice() {
		// Measured, not guessed: enumerating 191 voices per utterance cost 0.380 s
		// to the first sample against the spike's 0.218 s. The rule stays in
		// VoiceChoice; what this asserts is that the controller does not pay for it
		// before VoiceChoice decides whether it is needed.
		let subject = makeSubject()
		subject.controller.capture(ssml: "<speak>um</speak>", requestedBy: "ours")
		#expect(subject.catalogue.allVoicesReads == 0)
	}

	@Test("the voice list IS enumerated when the default is unusable")
	func theFallbackPathDoesEnumerate() {
		let subject = makeSubject(defaults: ["pt-BR": CaptureControllerTests.ours])
		subject.controller.capture(ssml: "<speak>um</speak>", requestedBy: "ours")
		#expect(subject.catalogue.allVoicesReads == 1)
		#expect(subject.synthesizer.spoken.first?.voice == CaptureControllerTests.brazilian)
	}

	@Test("a language stated in the SSML is used and reported as stated")
	func statedLanguageIsUsed() {
		let subject = makeSubject(defaults: ["en-US": AvailableVoice(
			identifier: "com.apple.voice.compact.en-US.Samantha", name: "Samantha", language: "en-US")])
		subject.controller.capture(ssml: "<speak xml:lang=\"en-US\">one two</speak>", requestedBy: "ours")
		#expect(subject.sink.field("utterance_language", ofKind: .synthesize) == .text("en-US"))
		#expect(subject.synthesizer.spoken.first?.voice.language == "en-US")
	}

	@Test("our own voice is never re-spoken with, so re-entrancy cannot happen")
	func ourVoiceIsNeverChosen() {
		let subject = makeSubject(defaults: ["pt-BR": CaptureControllerTests.ours], voices: [CaptureControllerTests.ours])
		subject.controller.capture(ssml: "<speak>um</speak>", requestedBy: "ours")
		#expect(subject.synthesizer.spoken.isEmpty)
		#expect(subject.sink.field("passthrough_voice", ofKind: .synthesize) == .text("<none>"))
	}

	@Test("no usable voice is reported by name, and the utterance still ends")
	func noVoiceIsNamedRatherThanHung() {
		let subject = makeSubject(defaults: [:], voices: [])
		subject.controller.capture(ssml: "<speak>um</speak>", requestedBy: "ours")
		#expect(subject.sink.field("passthrough_voice", ofKind: .synthesize) == .text("<none>"))
		#expect(subject.ring.isFinished)
	}

	@Test("warming up touches the catalogue and says nothing")
	func warmUpCostsOneLookupAndEmitsNothing() {
		// The point is a framework side effect -- the first voice lookup in a
		// process costs ~150 ms -- so what is asserted is that it happens, and that
		// it is not mistaken for an utterance by anything reading the feed.
		let subject = makeSubject()
		subject.controller.warmUp()
		#expect(subject.catalogue.defaultLookups == ["pt-BR"])
		#expect(subject.sink.events.isEmpty)
		#expect(subject.synthesizer.spoken.isEmpty)
	}

	// -- cancellation, which is the ordinary path -----------------------------

	@Test("a cancel is an ordinary event, not a fault")
	func cancelIsOrdinary() {
		// VoiceOver cancels before EVERY new utterance, so this runs at least as
		// often as capture does.
		let subject = makeSubject()
		subject.controller.capture(ssml: "<speak>um</speak>", requestedBy: "ours")
		subject.controller.cancel()
		#expect(subject.sink.events(ofKind: .cancel).count == 1)
		#expect(subject.synthesizer.cancelCount == 1)
	}

	@Test("the counters are read BEFORE the synthesizer is stopped")
	func statisticsPrecedeTheTruncation() {
		// Stopping truncates the ring, so reading afterwards would report the state
		// after the cut rather than the one that caused it.
		let subject = makeSubject()
		subject.controller.cancel()
		#expect(subject.synthesizer.calls == ["statistics", "cancel"])
	}

	@Test("the cancel event carries the ring and timing counters")
	func cancelCarriesTheEvidence() {
		let subject = makeSubject()
		subject.synthesizer.reported = SynthesisStatistics(
			prebufferMilliseconds: 170,
			callbackCount: 12,
			firstCallbackMilliseconds: 168,
			maxGapMilliseconds: 40,
			totalFrames: 242_688,
			spanMilliseconds: 451,
			sourceSampleRate: 22050,
			sourceChannels: 1,
			converted: false
		)
		subject.controller.cancel()
		#expect(subject.sink.field("prebuffer_ms", ofKind: .cancel) == .count(170))
		#expect(subject.sink.field("cb_frames", ofKind: .cancel) == .count(242_688))
		#expect(subject.sink.field("cb_span_ms", ofKind: .cancel) == .count(451))
		#expect(subject.sink.field("source_rate", ofKind: .cancel) == .number(22050))
		#expect(subject.sink.field("converted", ofKind: .cancel) == .flag(false))
		#expect(subject.sink.field("underruns", ofKind: .cancel) == .count(0))
	}

	@Test("a format nobody has seen yet is reported as absent rather than as zero")
	func unknownSourceFormatIsOmitted() {
		let subject = makeSubject()
		subject.controller.cancel()
		let event = subject.sink.events(ofKind: .cancel).last
		#expect(event?.fields["source_rate"] == nil)
		#expect(event?.fields["converted"] == nil)
	}

	@Test("the audio unit's own observations go through the same feed")
	func reportedEventsShareTheFeed() {
		let subject = makeSubject()
		subject.controller.report(
			CaptureEvent(kind: .audioUnitCreated, fields: ["cleared_darwin_bg": .flag(true)]))
		#expect(subject.sink.events(ofKind: .audioUnitCreated).count == 1)
	}

	// -- Rule 0: the voice the bridge named (13.6) -----------------------------

	@Test("the voice the bridge named on the marker is the one that speaks")
	func preferredVoiceIsUsed() {
		let subject = makeSubject(preferredVoice: CaptureControllerTests.arabic.identifier)
		subject.controller.capture(ssml: "<speak>oi</speak>", requestedBy: "any")
		// Named in the feed rather than inferred from the audio, which is spec
		// 0047 finding 18's whole point: the ear cannot tell these apart.
		#expect(
			subject.sink.field("passthrough_voice", ofKind: .synthesize)
				== .text(CaptureControllerTests.arabic.identifier))
	}

	@Test("a preferred voice this machine does not have degrades to the rules below it")
	func unknownPreferredVoiceDegrades() {
		let subject = makeSubject(preferredVoice: "com.example.a.voice.that.is.not.installed")
		subject.controller.capture(ssml: "<speak>oi</speak>", requestedBy: "any")
		#expect(
			subject.sink.field("passthrough_voice", ofKind: .synthesize)
				== .text(CaptureControllerTests.brazilian.identifier))
	}

	@Test("a preferred voice that is OURS is refused: rule 1 wins over rule 0")
	func preferredVoiceMayNotBeOurs() {
		let subject = makeSubject(preferredVoice: CaptureControllerTests.ours.identifier)
		subject.controller.capture(ssml: "<speak>oi</speak>", requestedBy: "any")
		#expect(
			subject.sink.field("passthrough_voice", ofKind: .synthesize)
				== .text(CaptureControllerTests.brazilian.identifier))
	}

	@Test("the marker is read ONCE per utterance, however many questions are asked of it")
	func oneReadPerUtterance() {
		// Both halves of the directive come from one read, so a marker refreshed
		// mid-utterance cannot answer one half about this session and the other
		// about the next.
		let subject = makeSubject(preferredVoice: CaptureControllerTests.arabic.identifier)
		subject.controller.capture(ssml: "<speak>oi</speak>", requestedBy: "any")
		#expect(subject.mode.reads == 1)
	}
}
