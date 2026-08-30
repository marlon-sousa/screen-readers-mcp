// Mirrors Sources/ScreenReaderWire/Commands/SetState.swift.

import Testing

@testable import ScreenReaderWire

@Suite("setState")
struct SetStateTests {
	@Test("an empty request asks for nothing, which is not the same as asking for none")
	func absentIsNotNone() throws {
		#expect(try WireJSON.decode(SetStateParams.self, "{}").browseMode == nil)
		#expect(try WireJSON.decode(SetStateParams.self, #"{"browseMode":"none"}"#).browseMode == BrowseMode.none)
	}

	@Test("a request that changed nothing answers with an empty changed list")
	func nothingChanged() throws {
		let json = """
		{"state":{"browseMode":"browse","speechMode":"talk","sleepMode":false,"inputHelp":false}}
		"""
		let result = try WireJSON.decode(SetStateResult.self, json)
		#expect(result.changed.isEmpty)
		#expect(result.state.browseMode == .browse)
	}

	@Test("the whole state comes back, so no second question is needed")
	func stateIsRequired() {
		#expect(throws: (any Error).self) {
			try WireJSON.decode(SetStateResult.self, #"{"changed":["browseMode"]}"#)
		}
	}
}
