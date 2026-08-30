// Mirrors Sources/ScreenReaderWire/Commands/Echo.swift.

import Testing

@testable import ScreenReaderWire

@Suite("echo")
struct EchoTests {
	@Test("a payload of any shape survives the round trip that echo exists to prove")
	func anyPayloadSurvives() throws {
		let json = #"{"payload":{"list":[1,"two",null,{"three":true}]}}"#
		let params = try WireJSON.decode(EchoParams.self, json)
		#expect(try WireJSON.encoded(EchoResult(payload: params.payload)) == WireJSON.value(json))
	}

	@Test("a scalar payload is a payload too")
	func scalarPayload() throws {
		#expect(try WireJSON.decode(EchoParams.self, #"{"payload":7}"#).payload == .int(7))
	}

	@Test("a missing payload is refused -- echo with nothing to echo is a fault")
	func payloadIsRequired() {
		#expect(throws: (any Error).self) {
			try WireJSON.decode(EchoParams.self, "{}")
		}
	}
}
