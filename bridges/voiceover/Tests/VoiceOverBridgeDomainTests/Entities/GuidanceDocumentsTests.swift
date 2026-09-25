// Mirrors Sources/VoiceOverBridgeDomain/Entities/GuidanceDocuments.swift.
// Reads every document through the real loader, so a Package.swift missing its `resources:` declaration fails here rather than at run time.

import Testing

@testable import VoiceOverBridgeDomain

@Suite("GuidanceDocuments")
struct GuidanceDocumentsTests {
	@Test("every persona the server can declare has a document, and gets the common half too")
	func everyPersonaComposes() throws {
		for persona in GuidanceDocuments.sections.keys {
			let composed = try GuidanceDocuments.guidance(for: persona)
			#expect(composed.recognised, "\(persona) should be recognised")
			#expect(composed.text.contains("Driving VoiceOver on macOS"))
			#expect(composed.text.count > 2000, "\(persona)'s document is suspiciously short")
		}
	}

	@Test("an UNRECOGNISED persona degrades: the common half, and it says what is missing")
	func unknownPersonaDegrades() throws {
		let composed = try GuidanceDocuments.guidance(for: "archaeologist")
		#expect(!composed.recognised)
		#expect(composed.text.contains("Driving VoiceOver on macOS"))
		#expect(composed.text.contains("No section for the persona you declared"))
	}

	@Test("an EMPTY persona takes the same path as an unknown one")
	func emptyPersonaDegrades() throws {
		let composed = try GuidanceDocuments.guidance(for: "")
		#expect(!composed.recognised)
		#expect(composed.text.contains("Driving VoiceOver on macOS"))
	}

	@Test("a document this build does not carry RAISES, and never returns empty")
	func aMissingDocumentRaises() {
		#expect(throws: GuidanceDocumentMissing.self) {
			try GuidanceDocuments.read("a-document-nobody-wrote")
		}
	}

	@Test("the common document carries the measurements the other entries paid for")
	func itCarriesTheMeasurements() throws {
		let text = try GuidanceDocuments.read(GuidanceDocuments.common)

		#expect(text.contains("Commands menu"))
		#expect(text.contains("vo+h"))
		#expect(!text.contains("press_gesture { gestures: [\"describe item"))

		#expect(text.contains("do not compose"))

		#expect(text.contains("LOCALIZED"))
		#expect(text.contains("AXRole"))

		#expect(text.contains("toggle web navigation dom or group"))

		#expect(text.contains("vo+m"))
		#expect(text.contains("Caps Lock"))
		#expect(text.contains("never passes the application"))
		#expect(text.contains("shifted character"))
	}

	@Test("THE `user` STANCE PRESSES KEYS, AND NOBODY HAS A DISPATCH CHANNEL")
	func theUserStancePressesKeys() throws {
		let text = try GuidanceDocuments.guidance(for: "user").text
		#expect(text.contains("Press the keys"))
		#expect(text.contains("vo+m"))
		#expect(text.contains("NOBODY'S NOW"))
		#expect(text.contains("vo+h"))
		#expect(text.contains("Accessibility grant"))
	}

	@Test("the `validator` stance presses keys too, and REPORTS what it cannot do")
	func theValidatorPressesKeys() throws {
		let text = try GuidanceDocuments.guidance(for: "validator").text
		#expect(text.contains("only keys"))
		#expect(text.contains("rebound"))
		#expect(text.contains("cannot dispatch one of the reader's commands by"))
	}

	@Test("the `expert` stance is told the dispatch channel is GONE, and where it went")
	func theExpertIsToldTheChannelIsGone() throws {
		let text = try GuidanceDocuments.guidance(for: "expert").text
		#expect(text.contains("That channel is gone"))
		#expect(text.contains("osascript"))
		// The phrase asserted must not span a line break, because the documents are wrapped prose.
		#expect(text.contains("you are not blocked"))
	}

	@Test("no document promises a capability this bridge does not serve")
	func itPromisesNothingAbsent() throws {
		let text = try GuidanceDocuments.read(GuidanceDocuments.common)
		#expect(text.contains("No braille content"))
		#expect(text.contains("No reader log"))
		#expect(text.contains("No settable state"))
	}
}
