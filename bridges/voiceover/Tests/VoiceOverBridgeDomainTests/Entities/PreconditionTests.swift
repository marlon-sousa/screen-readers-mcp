// Mirrors Sources/VoiceOverBridgeDomain/Entities/Precondition.swift.
//
// WHAT IS WORTH TESTING IN AN ENUMERATION OF PROSE is the property the type
// exists for: that a diagnosis and its recovery never travel apart, and that the
// recovery names something a HUMAN can actually do -- because by definition
// nothing else can fix a precondition.
//
// The count is asserted too, deliberately. Spec 0046 named two of these and spec
// 0047 removed one of them by making the bridge able to REPAIR it, so "one case"
// is a decision this file should have to be edited to change.

import Testing

@testable import VoiceOverBridgeDomain

@Suite("Precondition")
struct PreconditionTests {
	@Test("there is exactly ONE, and it is the one no API can set")
	func oneInstance() {
		// The capture voice's selection was the other until spec 0047's findings 16
		// and 17: the bridge writes that preference itself, live, so it is a state
		// the bridge repairs rather than a plea to a human.
		#expect(Precondition.allCases == [.readerScripting])
	}

	@Test("every case says what is lost AND what to do, in one rendering")
	func diagnosisAndRecoveryTravelTogether() {
		for precondition in Precondition.allCases {
			#expect(!precondition.summary.isEmpty)
			#expect(!precondition.recovery.isEmpty)
			let described = precondition.described
			#expect(described.contains(precondition.rawValue))
			#expect(described.contains(precondition.summary))
			#expect(described.contains(precondition.recovery))
		}
	}

	@Test("the recovery names the switch in the reader's own settings, not only the files")
	func theRecoveryIsActionable() {
		// A person cannot act on a path under /private/var/db. The files are named
		// too, because the next person to MEASURE this needs them -- the audience is
		// both, which is why the sentence carries both.
		let recovery = Precondition.readerScripting.recovery
		#expect(recovery.contains("VoiceOver Utility"))
		#expect(recovery.contains("SCREnableAppleScript"))
	}
}
