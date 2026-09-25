// Mirrors Sources/VoiceOverBridgeDomain/Entities/ProviderState.swift.

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
		#expect(ProviderState.published.observing(captured: true) == .capturing)
		#expect(ProviderState.notRegistered.observing(captured: true) == .capturing)
		#expect(ProviderState.selected.observing(captured: true) == .capturing)
	}

	@Test("and nothing arriving leaves the inference exactly as it was")
	func silenceChangesNothing() {
		for state in ProviderState.allCases {
			#expect(state.observing(captured: false) == state)
		}
	}

	@Test("a healthy, freshly selected session reports NO conditions")
	func selectedIsHealthy() {
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
		#expect(
			ProviderState.published.conditions
				== [.captureVoiceNotSelected, .captureVoiceNotOfferedByReader])
	}

	@Test("an UNHEARD session names the two conditions nothing can tell apart")
	func unheardNamesBoth() {
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
