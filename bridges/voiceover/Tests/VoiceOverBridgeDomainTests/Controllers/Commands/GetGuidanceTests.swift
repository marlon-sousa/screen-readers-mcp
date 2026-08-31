// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/GetGuidance.swift.
//
// The properties under test are the two the contract actually constrains: that
// the handler answers for THE SESSION'S persona and for no other, and that an
// unfamiliar persona degrades rather than failing. Everything about the documents
// themselves is GuidanceDocumentsTests' business.

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
		// Spec 0029, 4.3: a `persona` argument would let a `user` session read the
		// validator's document, which quietly undoes what declaring a stance is
		// for. The check is that params sent anyway are IGNORED rather than
		// honoured -- a handler that started reading them would fail here.
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
		// protocol.md §4, and it is a release argument rather than a courtesy: if
		// this could fail, adding a fourth persona to the server would mean
		// releasing every bridge in the field at the same time.
		let answer = try guidance(persona: "archaeologist")
		#expect(answer.persona == "archaeologist")
		#expect(!answer.recognised)
		// Still the larger half of what it needed, plus a paragraph saying what is
		// missing. Silence would leave the agent believing it had been instructed.
		#expect(answer.text.contains("Driving VoiceOver on macOS"))
		#expect(answer.text.contains("No section for the persona you declared"))
	}

	@Test("it does not move the reader and does not need the handshake's adapters")
	func itTouchesNothing() throws {
		// It composes files. The context it is handed here has no AdapterSet at
		// all, which is the strongest available statement that no port is reached:
		// a handler that touched one would crash rather than pass.
		let handler = GetGuidanceHandler()
		#expect(!handler.mutatesReader)
		#expect(!handler.availableBeforeHello)
		_ = try guidance(persona: "user")
	}
}
