// Mirrors Sources/VoiceOverBridgeDomain/Entities/SetupRung.swift.

import Testing

@testable import VoiceOverBridgeDomain

@Suite("SetupRung")
struct SetupRungTests {
	@Test("every rung has a summary, and none of them is empty")
	func allAreDescribed() {
		for rung in SetupRung.allCases {
			#expect(!rung.summary.isEmpty)
		}
	}

	@Test("a failure carries the rung, the cause and what the agent must do")
	func aFailureCarriesAllThree() {
		let message = SetupRung.registration.failed(
			"pluginkit does not list it", agentMustDo: "ask the human to run it by hand")
		#expect(message.contains("registration"))
		#expect(message.contains(SetupRung.registration.summary))
		#expect(message.contains("pluginkit does not list it"))
		#expect(message.contains("ask the human to run it by hand"))
	}

	@Test("EVERY rung renders the same shape, so a fifth one cannot answer differently")
	func theShapeIsUniform() {
		for rung in SetupRung.allCases {
			let message = rung.failed("because", agentMustDo: "do this")
			#expect(message.contains("'\(rung.rawValue)'"))
			#expect(message.contains("WHAT YOU MUST DO: do this"))
		}
	}

	@Test("the order of the cases is the order of the climb")
	func theOrderIsTheClimb() {
		#expect(
			SetupRung.allCases == [
				.permissions, .readerRunning, .registration, .voiceSelection, .captureProof,
			])
	}
}
