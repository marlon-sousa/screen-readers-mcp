// Mirrors Sources/ScreenReaderWire/Command.swift.
//
// The whole contract's command list is bound, not this bridge's subset, so the
// count below is the contract's -- and scripts/drift.py compares it with the
// schema's `commands` map rather than trusting either side.

import Testing

@testable import ScreenReaderWire

@Suite("Command")
struct CommandTests {
	@Test("every command in the contract is bound")
	func countMatchesTheContract() {
		#expect(Command.allCases.count == 26)
	}

	@Test("a command's raw value is its wire spelling")
	func rawValuesAreTheWireNames() {
		#expect(Command.hello.rawValue == "hello")
		#expect(Command.waitForSpeechToFinish.rawValue == "waitForSpeechToFinish")
		#expect(Command.getDocumentSnapshot.rawValue == "getDocumentSnapshot")
	}

	@Test("an unknown command name is not a Command, and that is data rather than a fault")
	func unknownNameIsNil() {
		// The registry answers "unknown command"; nothing fails to decode, which
		// is why Request.cmd is a String. See EnvelopeTests.
		#expect(Command(rawValue: "makeCoffee") == nil)
	}

	@Test("no two commands share a wire name")
	func namesAreUnique() {
		let names = Set(Command.allCases.map(\.rawValue))
		#expect(names.count == Command.allCases.count)
	}
}
