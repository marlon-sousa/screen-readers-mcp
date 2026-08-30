// Mirrors Sources/ScreenReaderWire/Commands/GetState.swift.

import Testing

@testable import ScreenReaderWire

@Suite("getState")
struct GetStateTests {
	@Test("the four fields are all required -- a partial state is not a state")
	func allFieldsRequired() {
		#expect(throws: (any Error).self) {
			try WireJSON.decode(StateResult.self, #"{"browseMode":"browse","speechMode":"talk","sleepMode":false}"#)
		}
	}

	@Test("speech mode is a raw string, because it is the reader's own vocabulary")
	func speechModeIsOpaque() throws {
		let json = #"{"browseMode":"focus","speechMode":"onDemand","sleepMode":false,"inputHelp":true}"#
		let state = try WireJSON.decode(StateResult.self, json)
		#expect(state.speechMode == "onDemand")
		#expect(state.inputHelp)
	}

	@Test("a state round-trips unchanged")
	func roundTrip() throws {
		let state = StateResult(browseMode: .browse, speechMode: "talk", sleepMode: true, inputHelp: false)
		#expect(try WireJSON.roundTrip(state) == state)
	}
}
