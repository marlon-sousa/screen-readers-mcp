// Mirrors Sources/VoiceOverBridgeAdapters/VoiceOverFocusInspector.swift.
//
// THE WHOLE ROUTE IS EXERCISED WITH NO READER PRESENT, and that is what the seams
// are for. The attribute query, the mapping into a snapshot and every "this is
// empty, not broken" rule are decisions in this adapter, so each is an ordinary
// unit test rather than something only the maintainer's machine could show --
// which matters more here than usual, because the answers a live machine gives
// depend on which window is in front.
//
// IT EXERCISED TWO ROUTES UNTIL 13.31, and the tests for the second one were
// deleted with it rather than left asserting a branch nothing can enter: without
// the Accessibility grant, `name` came from VoiceOver's own cursor over an
// AppleEvent. A session cannot exist without that grant now, because pressing keys
// is the only way this bridge drives the reader (spec 0055). What replaced those
// tests is one about the grant being REVOKED, which is the state that can still
// happen and the one an empty snapshot would misreport.
//
// NOTHING HERE COMPARES A STRING THE READER RENDERED. `AXRole` is a framework
// constant and the states come from booleans. That is the lane's no-reader-strings
// rule in its focus instance -- and it is why the deleted route is no loss to an
// assertion: the cursor answered `área de rolagem` on the maintainer's machine.

import Fakes
import Testing
import VoiceOverBridgeDomain

@testable import VoiceOverBridgeAdapters

@Suite("VoiceOverFocusInspector")
struct VoiceOverFocusInspectorTests {
	private func inspector(
		tree: FakeAccessibilityTree = FakeAccessibilityTree(),
		frontmost: FakeFrontmostApplication = FakeFrontmostApplication(),
		trust: FakeAccessibilityTrust = FakeAccessibilityTrust(trusted: true)
	) -> VoiceOverFocusInspector {
		VoiceOverFocusInspector(tree: tree, frontmost: frontmost, trust: trust)
	}

	private let button: [String: AccessibilityValue] = [
		"AXRole": .text("AXButton"),
		"AXTitle": .text("Save"),
		"AXValue": .text("on"),
		"AXFocused": .flag(true),
		"AXEnabled": .flag(true),
	]

	// -- which route answers ----------------------------------------------------

	@Test("it reads the accessibility tree, addressed to the frontmost pid")
	func theTreeRouteAnswers() throws {
		let tree = FakeAccessibilityTree(element: button)
		let snapshot = try inspector(tree: tree).focusInfo()

		#expect(snapshot.name == "Save")
		#expect(snapshot.role == "AXButton")
		// The pid the frontmost application answered with -- which is why that seam
		// is a collaborator and not a convenience: there is no system-wide element
		// that works (see AXAccessibilityTree's header).
		#expect(tree.queries.map(\.pid) == [4242])
	}

	@Test("A REVOKED GRANT IS A NAMED FAILURE, never an empty snapshot")
	func aRevokedGrantIsNamed() {
		// THE STATE THAT REPLACED THE CURSOR ROUTE. Every session holds this grant
		// at the handshake, so seeing it absent here means a human revoked it while
		// the session ran. Answering "nothing is focused" would send an agent
		// looking for a defect in the application under test, which is the class of
		// wrong answer `ReaderCondition`'s header exists to forbid.
		let tree = FakeAccessibilityTree(element: button)
		#expect(throws: FocusError.self) {
			try inspector(tree: tree, trust: FakeAccessibilityTrust(trusted: false)).focusInfo()
		}
		// AND IT ASKED THE TREE NOTHING. There is no half-answer to assemble from a
		// grant that is gone.
		#expect(tree.queries.isEmpty)
	}

	@Test("the grant is READ, never requested, and read once per call")
	func theTrustSeamIsOnlyRead() throws {
		// The seam has one method and it shows no dialog. This is the structural
		// half of 13.8's lever: focus cannot ask for the grant, because the object
		// it holds cannot be asked.
		let trust = FakeAccessibilityTrust(trusted: true)
		_ = try inspector(tree: FakeAccessibilityTree(element: button), trust: trust).focusInfo()
		#expect(trust.reads == 1)
		// It is a seam with ONE method, so there is nothing here that could ask.
	}

	@Test("A READ WITH NOTHING FOCUSED ANSWERS EMPTY, and reaches for nothing else")
	func thereIsNoFallbackBetweenRoutes() throws {
		// THE RULE OUTLIVED THE SECOND ROUTE ON PURPOSE. It used to say: a tree read
		// that finds nothing must not quietly ask the VoiceOver cursor, because the
		// two are different views and an answer that silently came from the other is
		// one an agent cannot interpret. There is one view now, so the rule is
		// trivially kept -- and it is written down here so that a future second route
		// does not arrive as a silent fallback.
		let snapshot = try inspector(tree: FakeAccessibilityTree(element: nil)).focusInfo()
		#expect(snapshot.name.isEmpty)
	}

	// -- what the tree route asks for, and what it makes of the answer -----------

	@Test("the query names AXRole and never AXRoleDescription, which is the localized one")
	func theAttributeQuery() throws {
		let tree = FakeAccessibilityTree(element: button)
		_ = try inspector(tree: tree, trust: FakeAccessibilityTrust(trusted: true)).focusInfo()
		let asked = try #require(tree.queries.first).attributes
		#expect(asked.contains("AXRole"))
		#expect(asked.contains("AXTitle"))
		#expect(asked.contains("AXDescription"))
		#expect(asked.contains("AXValue"))
		// THE ONE THAT MUST NEVER BE ASKED FOR: `AXRoleDescription` is `AXButton`
		// rendered into the user's language, so a `role` built from it would mean
		// something different on the maintainer's Portuguese machine.
		#expect(!asked.contains("AXRoleDescription"))
	}

	@Test("AXTitle wins over AXDescription, and an element with neither has no name")
	func theNamePreference() {
		#expect(
			VoiceOverFocusInspector.name(from: ["AXTitle": .text("Save"), "AXDescription": .text("Store")])
				== "Save")
		#expect(VoiceOverFocusInspector.name(from: ["AXDescription": .text("Store")]) == "Store")
		// An unlabelled control is exactly what an agent testing accessibility is
		// hunting for, so "no name" is an answer.
		#expect(VoiceOverFocusInspector.name(from: ["AXRole": .text("AXButton")]).isEmpty)
	}

	@Test("states come from BOOLEANS, and only when the attribute is there")
	func theStates() {
		#expect(
			VoiceOverFocusInspector.states(from: [
				"AXFocused": .flag(true), "AXSelected": .flag(true), "AXEnabled": .flag(false),
			]) == ["focused", "selected", "disabled"])
		// `AXEnabled` is interesting when FALSE; the others when true.
		#expect(VoiceOverFocusInspector.states(from: ["AXEnabled": .flag(true)]).isEmpty)
		#expect(VoiceOverFocusInspector.states(from: ["AXFocused": .flag(false)]).isEmpty)
		// AN ABSENT ATTRIBUTE CONTRIBUTES NOTHING: "not selected" and "has no
		// notion of selection" are different, and only the first is worth a word.
		#expect(VoiceOverFocusInspector.states(from: [:]).isEmpty)
	}

	@Test("`value` renders text, flags and numbers -- and a whole number keeps no decimal point")
	func theValueRendering() {
		#expect(VoiceOverFocusInspector.rendered(.text("on")) == "on")
		#expect(VoiceOverFocusInspector.rendered(.flag(true)) == "true")
		// A checkbox reads `1`, not `1.0`: an agent comparing values should not
		// have to know that AX answered a CFNumber.
		#expect(VoiceOverFocusInspector.rendered(.number(1)) == "1")
		#expect(VoiceOverFocusInspector.rendered(.number(0.5)) == "0.5")
		// Absent and unrenderable both answer nil, which is the one place the wire
		// shape cannot say more than it does.
		#expect(VoiceOverFocusInspector.rendered(nil) == nil)
		#expect(VoiceOverFocusInspector.rendered(.opaque) == nil)
	}

	@Test("a flag where text belongs is not coerced into a role")
	func nonTextAttributesAreNotCoercedIntoNames() throws {
		let snapshot = try inspector(
			tree: FakeAccessibilityTree(element: ["AXRole": .flag(true), "AXTitle": .number(3)]),
			trust: FakeAccessibilityTrust(trusted: true)
		).focusInfo()
		#expect(snapshot.role.isEmpty)
		#expect(snapshot.name.isEmpty)
	}

	// -- what is empty, and what is a fault -------------------------------------

	@Test("NOTHING FOCUSED IS AN ANSWER, and `appModule` still arrives")
	func nothingFocusedIsNotAFault() throws {
		// This is what VoiceOver's own process looks like ALWAYS -- it publishes no
		// accessibility tree of its own (spec 0047, finding 5) -- and what an
		// application between windows looks like. Neither is a reader fault.
		let snapshot = try inspector(
			tree: FakeAccessibilityTree(element: nil), trust: FakeAccessibilityTrust(trusted: true)
		).focusInfo()
		#expect(snapshot.name.isEmpty)
		#expect(snapshot.value == nil)
		#expect(snapshot.appModule == "com.apple.TextEdit")
	}

	@Test("a tree that refuses outright is a FocusError carrying the AX number")
	func aRefusedTreeIsAnError() {
		let tree = FakeAccessibilityTree(element: button)
		tree.failure = AccessibilityTreeFailure(code: -25211, description: "apiDisabled")
		#expect(throws: FocusError.self) {
			try inspector(tree: tree, trust: FakeAccessibilityTrust(trusted: true)).focusInfo()
		}
	}

	@Test("with nothing in front, it answers empty rather than addressing pid 0")
	func nothingInFront() throws {
		let tree = FakeAccessibilityTree(element: button)
		let snapshot = try inspector(
			tree: tree, frontmost: FakeFrontmostApplication(application: nil)
		).focusInfo()

		#expect(snapshot.appModule == nil)
		// The tree needs a pid to address an application element; there is none, so
		// the question is not put. See AXAccessibilityTree's header on why there is
		// no system-wide element to fall back to.
		#expect(tree.queries.isEmpty)
	}

	@Test("an application with no bundle identifier reports a null appModule, not an empty one")
	func anApplicationWithoutABundleIdentifier() throws {
		let snapshot = try inspector(
			tree: FakeAccessibilityTree(element: button),
			frontmost: FakeFrontmostApplication(
				application: ApplicationIdentity(bundleIdentifier: nil, processIdentifier: 99)),
			trust: FakeAccessibilityTrust(trusted: true)
		).focusInfo()
		#expect(snapshot.appModule == nil)
		#expect(snapshot.name == "Save")
	}
}
