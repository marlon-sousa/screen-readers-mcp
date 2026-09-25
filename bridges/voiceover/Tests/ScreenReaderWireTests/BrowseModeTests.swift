// Mirrors Sources/ScreenReaderWire/BrowseMode.swift.

import Testing

@testable import ScreenReaderWire

@Suite("BrowseMode")
struct BrowseModeTests {
	@Test("the three answers are browse, focus and none")
	func vocabulary() {
		#expect(BrowseMode.allCases.map(\.rawValue) == ["browse", "focus", "none"])
	}

	@Test("`none` is a reported mode, not an absent one")
	func noneIsAValue() throws {
		let state = try WireJSON.decode(
			StateResult.self,
			#"{"browseMode":"none","speechMode":"talk","sleepMode":false,"inputHelp":false}"#
		)
		#expect(state.browseMode == BrowseMode.none)
	}
}
