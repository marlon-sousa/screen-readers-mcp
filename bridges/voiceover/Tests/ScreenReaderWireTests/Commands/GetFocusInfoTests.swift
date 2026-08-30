// Mirrors Sources/ScreenReaderWire/Commands/GetFocusInfo.swift.
//
// The suite that earns its keep here is the required-and-nullable one: Swift's
// synthesized decoder folds "sent as null" and "not sent at all" into the same
// nil, and the contract distinguishes them.

import Testing

@testable import ScreenReaderWire

@Suite("getFocusInfo")
struct GetFocusInfoTests {
	@Test("a null value is an answer: the element has none")
	func nullValueIsAnAnswer() throws {
		let json = #"{"name":"OK","role":"button","states":["focused"],"value":null,"appModule":"Finder"}"#
		let result = try WireJSON.decode(FocusInfoResult.self, json)
		#expect(result.value == nil)
		#expect(result.appModule == "Finder")
	}

	@Test("a missing value is a fault: the frame forgot a required field")
	func missingValueIsAFault() {
		let json = #"{"name":"OK","role":"button","states":["focused"],"appModule":"Finder"}"#
		#expect(throws: (any Error).self) {
			try WireJSON.decode(FocusInfoResult.self, json)
		}
	}

	@Test("both nullable fields travel as explicit nulls, never as absent keys")
	func nullsAreEmitted() throws {
		let result = FocusInfoResult(name: "", role: "", states: [], value: nil, appModule: nil)
		#expect(try WireJSON.keys(of: result) == ["appModule", "name", "role", "states", "value"])
		#expect(try WireJSON.encoded(result) == .object([
			"name": .string(""),
			"role": .string(""),
			"states": .array([]),
			"value": .null,
			"appModule": .null,
		]))
	}

	@Test("a thin answer is still a valid one, and says nothing about why it is thin")
	func thinAnswerIsValid() throws {
		// Without the Accessibility grant this bridge answers with empty role and
		// states, and the shape has nowhere to say which route answered -- the
		// guidance document carries that.
		let json = #"{"name":"","role":"","states":[],"value":null,"appModule":null}"#
		#expect(try WireJSON.decode(FocusInfoResult.self, json).states.isEmpty)
	}
}
