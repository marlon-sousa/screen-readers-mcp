// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/Echo.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("EchoHandler")
struct EchoTests {
	private func context() -> SessionContext {
		SessionContext(clock: FakeClock(), transcript: FakeTranscript(), attended: true, close: { _ in })
	}

	@Test("whatever it is given comes back unchanged, including a nested object")
	func itRoundTrips() throws {
		let payload = JSONValue.object([
			"nested": .array([.int(1), .string("two"), .bool(true), .null]),
			"number": .double(1.5),
		])
		let result = try EchoHandler().execute(
			context(), Request(id: 7, cmd: Command.echo.rawValue, params: ["payload": payload])
		) as? EchoResult
		#expect(try #require(result).payload == payload)
	}

	@Test("a request with no payload at all is a validation error, not an empty echo")
	func aMissingPayloadIsAFault() {
		#expect(throws: ValidationError.self) {
			try EchoHandler().execute(context(), Request(id: 8, cmd: Command.echo.rawValue))
		}
	}
}
