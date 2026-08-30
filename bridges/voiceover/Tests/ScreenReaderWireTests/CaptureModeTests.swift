// Mirrors Sources/ScreenReaderWire/CaptureMode.swift.

import Testing

@testable import ScreenReaderWire

@Suite("CaptureMode")
struct CaptureModeTests {
	@Test("the two modes travel as their own names")
	func rawValues() throws {
		#expect(try WireJSON.encoded(CaptureMode.silent) == .string("silent"))
		#expect(try WireJSON.encoded(CaptureMode.live) == .string("live"))
	}

	@Test("a third mode is refused rather than accepted as something")
	func unknownModeIsRefused() {
		// The opposite of Capability, and deliberately: a mode is an instruction
		// this bridge must carry out, so one it cannot recognise it must refuse.
		#expect(throws: (any Error).self) {
			try WireJSON.decode(CaptureMode.self, #""whisper""#)
		}
	}
}
