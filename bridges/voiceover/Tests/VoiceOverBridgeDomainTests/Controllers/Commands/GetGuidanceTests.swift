// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/GetGuidance.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("GetGuidanceHandler")
struct GetGuidanceTests {
	private func context(persona: String) -> SessionContext {
		let context = SessionContext(
			clock: FakeClock(), transcript: FakeTranscript(), attended: true, close: { _ in })
		context.persona = persona
		return context
	}

	private func guidance(persona: String) throws -> GetGuidanceResult {
		let result = try GetGuidanceHandler().execute(
			context(persona: persona), Request(id: 1, cmd: Command.getGuidance.rawValue))
		return try #require(result as? GetGuidanceResult)
	}

	@Test("it answers for the session's own persona")
	func itAnswersForTheSessionPersona() throws {
		let answer = try guidance(persona: "validator")
		#expect(answer.persona == "validator")
		#expect(answer.recognised)
		#expect(answer.text.contains("Holding the `validator` stance on VoiceOver"))
	}

	@Test("it takes NO parameters, so no session can fetch another stance's instructions")
	func itTakesNoParameters() throws {
		let request = Request(
			id: 1, cmd: Command.getGuidance.rawValue,
			params: ["persona": .string("expert")])
		let result = try GetGuidanceHandler().execute(context(persona: "user"), request)
		let answer = try #require(result as? GetGuidanceResult)
		#expect(answer.persona == "user")
		#expect(answer.text.contains("Holding the `user` stance on VoiceOver"))
	}

	@Test("an unrecognised persona is answered, not refused")
	func anUnknownPersonaDegrades() throws {
		let answer = try guidance(persona: "archaeologist")
		#expect(answer.persona == "archaeologist")
		#expect(!answer.recognised)
		#expect(answer.text.contains("Driving VoiceOver on macOS"))
		#expect(answer.text.contains("No section for the persona you declared"))
	}

	@Test("it does not move the reader and does not need the handshake's adapters")
	func itTouchesNothing() throws {
		let handler = GetGuidanceHandler()
		#expect(!handler.mutatesReader)
		#expect(!handler.availableBeforeHello)
		_ = try guidance(persona: "user")
	}
}
