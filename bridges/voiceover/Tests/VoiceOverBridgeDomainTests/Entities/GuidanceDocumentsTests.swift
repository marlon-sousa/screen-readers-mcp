// Mirrors Sources/VoiceOverBridgeDomain/Entities/GuidanceDocuments.swift.
//
// THE MOST IMPORTANT THING THIS FILE DOES IS READ EVERY DOCUMENT THROUGH THE
// REAL LOADER. The Swift half of the embedded-document trap is a RUNTIME one --
// `Bundle.module` resolves a bundle SwiftPM generated, and a build assembled
// without it fails when an agent asks rather than when anybody compiles. So the
// suite exists partly to make that failure arrive in CI: if the `resources:`
// declaration is dropped from Package.swift, every test here goes red.
//
// WHAT IT DELIBERATELY DOES NOT ASSERT: the prose. The documents are written and
// revised as writing, and a test that pinned sentences would make every edit a
// two-file change for no gain. What is asserted is the STRUCTURE the contract
// depends on -- that each persona gets the common half, that an unknown one
// degrades rather than failing, and that the reader-specific claims the other
// entries paid to measure are actually present.

import Testing

@testable import VoiceOverBridgeDomain

@Suite("GuidanceDocuments")
struct GuidanceDocumentsTests {
	@Test("every persona the server can declare has a document, and gets the common half too")
	func everyPersonaComposes() throws {
		for persona in GuidanceDocuments.sections.keys {
			let composed = try GuidanceDocuments.guidance(for: persona)
			#expect(composed.recognised, "\(persona) should be recognised")
			// The common section is the LARGER half and every stance needs it: it
			// describes the reader, not the stance.
			#expect(composed.text.contains("Driving VoiceOver on macOS"))
			#expect(composed.text.count > 2000, "\(persona)'s document is suspiciously short")
		}
	}

	@Test("an UNRECOGNISED persona degrades: the common half, and it says what is missing")
	func unknownPersonaDegrades() throws {
		// protocol.md §4: a bridge must not reject a persona it does not know, or
		// adding a fourth to the server would mean a synchronised release across
		// every bridge in the field. This is that rule, checked.
		let composed = try GuidanceDocuments.guidance(for: "archaeologist")
		#expect(!composed.recognised)
		#expect(composed.text.contains("Driving VoiceOver on macOS"))
		#expect(composed.text.contains("No section for the persona you declared"))
	}

	@Test("an EMPTY persona takes the same path as an unknown one")
	func emptyPersonaDegrades() throws {
		// A server predating spec 0029 sends nothing. From this side "I do not know
		// that stance" and "you named no stance" call for the same document, so the
		// absence must not be a special case that fails differently.
		let composed = try GuidanceDocuments.guidance(for: "")
		#expect(!composed.recognised)
		#expect(composed.text.contains("Driving VoiceOver on macOS"))
	}

	@Test("a document this build does not carry RAISES, and never returns empty")
	func aMissingDocumentRaises() {
		// The whole reason this loader exists rather than a `?? ""`. An empty
		// document reads to an agent as "this reader has nothing to say", which is
		// a very different and much worse answer than "the build is broken" -- and
		// the agent would act on it.
		#expect(throws: GuidanceDocumentMissing.self) {
			try GuidanceDocuments.read("a-document-nobody-wrote")
		}
	}

	@Test("the common document carries the measurements the other entries paid for")
	func itCarriesTheMeasurements() throws {
		// These are not prose assertions: each is a FINDING that cost a live
		// measurement, and the board entry names them as what this document owes.
		// A rewrite that dropped one would be dropping the reason the document is
		// worth serving.
		let text = try GuidanceDocuments.read(GuidanceDocuments.common)

		// 13.7: a gesture here is a command name, not a keystroke.
		#expect(text.contains("describe item in voiceover cursor"))
		#expect(text.contains("Command does not exist (6)"))

		// 13.8: `press_gesture` reaches commands and single keys, and NOT chords,
		// because the modifier commands do not compose -- and a chord needs
		// `type_text`'s route and its grant.
		#expect(text.contains("do not compose"))
		#expect(text.contains("tab key"))

		// 13.9: the VoiceOver cursor's answer is LOCALIZED and not comparable
		// across machines, while the tree's AXRole is.
		#expect(text.contains("LOCALIZED"))
		#expect(text.contains("AXRole"))

		// 13.11's own half: how state is read on a reader that cannot be asked.
		#expect(text.contains("toggle web navigation dom or group"))
	}

	@Test("no document promises a capability this bridge does not serve")
	func itPromisesNothingAbsent() throws {
		// The failure the capability gate exists to prevent, in its documentation
		// form: an agent told to reach for a tool that is not there. Braille, the
		// reader log, state and document snapshots are all absent on this reader,
		// and the common document says so -- so it must not ALSO name them as
		// things to use.
		let text = try GuidanceDocuments.read(GuidanceDocuments.common)
		#expect(text.contains("No braille content"))
		#expect(text.contains("No reader log"))
		#expect(text.contains("No settable state"))
	}
}
