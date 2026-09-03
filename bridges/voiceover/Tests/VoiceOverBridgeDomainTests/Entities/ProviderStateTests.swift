// Mirrors Sources/VoiceOverBridgeDomain/Entities/ProviderState.swift.
//
// The whole value of five states over one boolean is that each one says
// something DIFFERENT to a human, so that is what this suite asserts: the
// ordering that gates a silent session, the promotion that only evidence can
// make, and the fact that a healthy handshake reports no conditions while an
// unexplained silence reports both of the two nothing can tell apart.

import Testing

@testable import VoiceOverBridgeDomain

@Suite("ProviderState")
struct ProviderStateTests {
	@Test("the states are ordered, and only the top two can capture")
	func orderingGatesCapture() {
		#expect(ProviderState.notRegistered < .registered)
		#expect(ProviderState.registered < .published)
		#expect(ProviderState.published < .selected)
		#expect(ProviderState.selected < .capturing)
		#expect(ProviderState.published.canCapture == false)
		#expect(ProviderState.selected.canCapture)
		#expect(ProviderState.capturing.canCapture)
	}

	@Test("capturing is promoted by EVIDENCE, and never claimed without it")
	func promotionNeedsEvidence() {
		#expect(ProviderState.selected.observing(captured: true) == .capturing)
		#expect(ProviderState.selected.observing(captured: false) == .selected)
	}

	@Test("AN UTTERANCE THAT ARRIVED PROMOTES FROM ANY STATE -- 13.26")
	func evidenceBeatsInference() {
		// This test asserted the OPPOSITE until 13.26, on the reasoning that
		// utterances cannot have arrived through a voice the reader is not using --
		// sound reasoning on a false premise. Every state below `capturing` is
		// INFERRED, and one of the questions the inference asks (does VoiceOver
		// offer our voice?) goes over AppleScript, which a careful user switches
		// off. Measured 2026-09-02: `poe conformance` refused a session on a machine
		// whose extension was registered, enabled and published, because it could
		// not interrogate the reader.
		//
		// An utterance arriving proves everything beneath it -- there is no other
		// way it could have got here.
		#expect(ProviderState.published.observing(captured: true) == .capturing)
		#expect(ProviderState.notRegistered.observing(captured: true) == .capturing)
		#expect(ProviderState.selected.observing(captured: true) == .capturing)
	}

	@Test("and nothing arriving leaves the inference exactly as it was")
	func silenceChangesNothing() {
		// The inference is still what says WHY, when there is nothing to hear.
		for state in ProviderState.allCases {
			#expect(state.observing(captured: false) == state)
		}
	}

	@Test("a healthy, freshly selected session reports NO conditions")
	func selectedIsHealthy() {
		// Reporting two possible faults at every handshake would train a reader to
		// ignore them, and "nothing has been said yet" is the normal state of a
		// session that has just started.
		#expect(ProviderState.selected.conditions.isEmpty)
		#expect(ProviderState.capturing.conditions.isEmpty)
	}

	@Test("an unregistered or unpublished voice names the provider condition")
	func theProviderConditions() {
		#expect(ProviderState.notRegistered.conditions == [.providerNotRunning])
		#expect(ProviderState.registered.conditions == [.providerNotRunning])
	}

	@Test("published-but-not-selected names BOTH the settings fault and the invisible one")
	func publishedNamesTheInvisibleCondition() {
		// Spec 0047, finding 6: the voice can be published system-wide and absent
		// from VoiceOver's own picker at the same moment, with the extension
		// registered and alive. If the bridge's own selection did not stick, that
		// is the likeliest reason -- and it is not one anything here can rule out.
		#expect(
			ProviderState.published.conditions
				== [.captureVoiceNotSelected, .captureVoiceNotOfferedByReader])
	}

	@Test("an UNHEARD session names the two conditions nothing can tell apart")
	func unheardNamesBoth() {
		// Selected, and still nothing captured: the provider may have died, or the
		// reader may never have offered the voice. No signal available outside
		// VoiceOver separates them, so both are named with both recoveries rather
		// than one being guessed at.
		#expect(
			ProviderState.selected.unheardConditions
				== [.providerNotRunning, .captureVoiceNotOfferedByReader])
		#expect(ProviderState.capturing.unheardConditions.isEmpty)
		#expect(ProviderState.notRegistered.unheardConditions == [.providerNotRunning])
	}

	@Test("the report carries the diagnosis AND every recovery, so they cannot travel apart")
	func theReportCarriesBoth() {
		let report = ProviderState.published.report
		#expect(report.contains(ProviderState.published.diagnosis))
		#expect(report.contains(ReaderCondition.captureVoiceNotSelected.recovery))
		#expect(report.contains(ReaderCondition.captureVoiceNotOfferedByReader.recovery))
	}

	@Test("every state says something different about the machine")
	func everyStateHasItsOwnDiagnosis() {
		let diagnoses = Set(ProviderState.allCases.map(\.diagnosis))
		#expect(diagnoses.count == ProviderState.allCases.count)
	}
}
