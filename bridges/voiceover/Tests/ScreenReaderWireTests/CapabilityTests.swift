// Mirrors Sources/ScreenReaderWire/Capability.swift.

import Testing

@testable import ScreenReaderWire

@Suite("Capability")
struct CapabilityTests {
	@Test("a capability travels as a bare string, not as an object")
	func encodesAsAString() throws {
		#expect(try WireJSON.encoded(Capability.speech) == .string("speech"))
	}

	@Test("a capability a newer peer invented decodes, and is retained verbatim")
	func unknownCapabilityIsKept() throws {
		let announced = try WireJSON.decode([Capability].self, #"["speech","telepathy"]"#)
		#expect(announced == [.speech, Capability(rawValue: "telepathy")])
		#expect(announced[1].rawValue == "telepathy")
	}

	@Test("but it is not pretended to be known")
	func unknownCapabilityIsNotKnown() {
		#expect(Capability.speech.isKnown)
		#expect(!Capability(rawValue: "telepathy").isKnown)
	}

	@Test("the known vocabulary is the contract's eleven")
	func knownVocabulary() {
		#expect(Capability.known.count == 11)
		#expect(Capability.known.contains(.guidance))
	}

	@Test("this bridge's six are all known ones")
	func voiceOverSetIsWithinTheVocabulary() {
		let voiceOver: Set<Capability> = [.speech, .gestures, .typing, .focus, .interact, .guidance]
		#expect(voiceOver.isSubset(of: Capability.known))
	}
}
