// Mirrors Sources/ScreenReaderWire/Commands/PressGesture.swift.

import Testing

@testable import ScreenReaderWire

@Suite("pressGesture")
struct PressGestureTests {
	@Test("the grace window defaults to the contract's 100 ms")
	func graceDefaults() throws {
		let params = try WireJSON.decode(PressGestureParams.self, #"{"gestures":["kb:downArrow"]}"#)
		#expect(params.graceMs == 100)
		#expect(params.announce.isEmpty)
	}

	@Test("zero opts out of the wait, and is not read as unset")
	func zeroGraceIsMeant() throws {
		let params = try WireJSON.decode(PressGestureParams.self, #"{"gestures":["kb:tab"],"graceMs":0}"#)
		#expect(params.graceMs == 0)
	}

	@Test("a call with no gestures is refused")
	func gesturesAreRequired() {
		#expect(throws: (any Error).self) {
			try WireJSON.decode(PressGestureParams.self, #"{"graceMs":50}"#)
		}
	}

	@Test("each press owns its own half-open speech range")
	func pressesCarryTheirOwnRanges() throws {
		let json = """
		{"pressed":[{"gesture":"kb:tab","speechFrom":4,"speechTo":6},\
		{"gesture":"kb:tab","speechFrom":6,"speechTo":7}],\
		"speech":[],"speechFrom":4,"speechTo":7}
		"""
		let result = try WireJSON.decode(GestureResult.self, json)
		#expect(result.pressed.map(\.speechFrom) == [4, 6])
		#expect(result.speechTo == 7)
	}

	@Test("a reader that cannot report its state simply omits it")
	func stateIsAbsentWhenUnreadable() throws {
		// This bridge's own answer: VoiceOver's toggles are drivable and not
		// readable, so `state` stays nil rather than carrying a guess.
		let json = #"{"pressed":[],"speech":[],"speechFrom":0,"speechTo":0}"#
		#expect(try WireJSON.decode(GestureResult.self, json).state == nil)
	}
}
