// Mirrors Sources/ScreenReaderWire/Commands/GetLog.swift.
//
// Not implemented by this bridge -- VoiceOver emits no diagnostic log of its own
// -- and bound anyway. The defaults below are the ones that keep a log slice
// from being incomplete by default.

import Testing

@testable import ScreenReaderWire

@Suite("getLog")
struct GetLogTests {
	@Test("an empty request is bounded: one window, two hundred entries")
	func boundsDefault() throws {
		let params = try WireJSON.decode(GetLogParams.self, "{}")
		#expect(params.windows == 1)
		#expect(params.maxEntries == 200)
		#expect(params.commandId == nil)
		#expect(params.minLevel == nil)
		#expect(params.contains == nil)
	}

	@Test("an empty filter list is not the same as no filter")
	func emptyFilterIsMeant() throws {
		let params = try WireJSON.decode(GetLogParams.self, #"{"contains":[]}"#)
		#expect(params.contains == [])
	}

	@Test("the slice reports what it left out as well as what it carries")
	func sliceReportsItsOwnBounds() throws {
		let json = """
		{"text":"...","entries":200,"matched":812,"truncated":true,"nextPosition":9001,\
		"capturedAtLevel":"debug"}
		"""
		let result = try WireJSON.decode(LogSliceResult.self, json)
		#expect(result.matched == 812)
		#expect(result.truncated)
		#expect(result.capturedAtLevel == .debug)
		#expect(result.fromCommandId == nil)
	}

	@Test("the level the log was captured at is required, because it bounds every filter")
	func capturedAtLevelRequired() {
		let json = #"{"text":"","entries":0,"matched":0,"truncated":false,"nextPosition":0}"#
		#expect(throws: (any Error).self) {
			try WireJSON.decode(LogSliceResult.self, json)
		}
	}
}
