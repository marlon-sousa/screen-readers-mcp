// Mirrors Sources/VoiceOverBridgeAdapters/VoiceOverFocusInspector.swift.
//
// BOTH ROUTES ARE EXERCISED WITH NO READER PRESENT, and that is what the three
// seams are for. The route choice, the attribute query, the mapping into a
// snapshot and every "this is empty, not broken" rule are decisions in this
// adapter, so each is an ordinary unit test rather than something only the
// maintainer's machine could show -- which matters more here than usual, because
// the answers a live machine gives depend on which window is in front.
//
// NOTHING HERE COMPARES A STRING THE READER RENDERED. `AXRole` is a framework
// constant and the states come from booleans; `missing value` is AppleScript's
// own token. That is the lane's no-reader-strings rule in its focus instance.

import Fakes
import Testing
import VoiceOverBridgeDomain

@testable import VoiceOverBridgeAdapters

@Suite("VoiceOverFocusInspector")
struct VoiceOverFocusInspectorTests {
	private func inspector(
		tree: FakeAccessibilityTree = FakeAccessibilityTree(),
		scripts: FakeAppleScriptRunner = FakeAppleScriptRunner(),
		frontmost: FakeFrontmostApplication = FakeFrontmostApplication(),
		trust: FakeAccessibilityTrust = FakeAccessibilityTrust()
	) -> VoiceOverFocusInspector {
		VoiceOverFocusInspector(tree: tree, scripts: scripts, frontmost: frontmost, trust: trust)
	}

	private let button: [String: AccessibilityValue] = [
		"AXRole": .text("AXButton"),
		"AXTitle": .text("Save"),
		"AXValue": .text("on"),
		"AXFocused": .flag(true),
		"AXEnabled": .flag(true),
	]

	// -- which route answers ----------------------------------------------------

	@Test("WITH THE GRANT it reads the accessibility tree, addressed to the frontmost pid")
	func theTreeRouteIsChosenWhenTrusted() throws {
		let tree = FakeAccessibilityTree(element: button)
		let scripts = FakeAppleScriptRunner()
		let snapshot = try inspector(
			tree: tree, scripts: scripts, trust: FakeAccessibilityTrust(trusted: true)
		).focusInfo()

		#expect(snapshot.name == "Save")
		#expect(snapshot.role == "AXButton")
		// The pid the frontmost application answered with -- which is why that seam
		// is asked on both routes and not only on this one.
		#expect(tree.queries.map(\.pid) == [4242])
		// AND NOTHING WENT TO THE READER. The two routes are alternatives, not a
		// belt and braces: a cursor read here would cost a subprocess per command
		// for an answer nothing uses.
		#expect(scripts.scripts.isEmpty)
	}

	@Test("WITHOUT THE GRANT it asks the VoiceOver cursor, and the script text is the contract")
	func theCursorRouteIsChosenWhenUntrusted() throws {
		let tree = FakeAccessibilityTree(element: button)
		let scripts = FakeAppleScriptRunner()
		scripts.defaultAnswer = "Ok button"
		let snapshot = try inspector(tree: tree, scripts: scripts).focusInfo()

		#expect(snapshot.name == "Ok button")
		#expect(
			scripts.scripts == [
				"tell application \"VoiceOver\" to return text under cursor of vo cursor"
			])
		// THE VO CURSOR, NOT THE KEYBOARD CURSOR -- the dictionary exposes both and
		// they are two views that only usually agree (spec 0046). Asserted as text
		// because the script IS the decision this adapter makes.
		#expect(scripts.scripts[0].contains("vo cursor"))
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
	}

	@Test("NO ROUTE FALLS BACK TO THE OTHER: a trusted read with nothing focused answers empty")
	func thereIsNoFallbackBetweenRoutes() throws {
		let scripts = FakeAppleScriptRunner()
		scripts.defaultAnswer = "something the cursor would have said"
		let snapshot = try inspector(
			tree: FakeAccessibilityTree(element: nil),
			scripts: scripts,
			trust: FakeAccessibilityTrust(trusted: true)
		).focusInfo()

		#expect(snapshot.name.isEmpty)
		// The grant picks the route and the route answers. An answer that silently
		// came from the other view is one an agent cannot interpret.
		#expect(scripts.scripts.isEmpty)
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

	@Test("`missing value` from the cursor is EMPTY, not an error")
	func missingValueIsEmpty() throws {
		// The same confound from the other end, and the reason this is a mapping
		// rather than a `throw`: a cursor sitting on a process with nothing to read
		// answers AppleScript's own null token, and it looks exactly like a dead
		// reader.
		let scripts = FakeAppleScriptRunner()
		scripts.defaultAnswer = "missing value"
		let snapshot = try inspector(scripts: scripts).focusInfo()
		#expect(snapshot.name.isEmpty)
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

	@Test("the AppleEvents failures are named, with the recovery each one needs")
	func theCursorFailuresAreExplained() {
		// THE NUMBERS ARE `VoiceOverGestureSender`'S, reused rather than copied:
		// they cost live measurements to learn, and two adapters with their own
		// copies is one drift away from two answers about one machine.
		let notAuthorized = VoiceOverFocusInspector.explain(
			AppleScriptError(number: -1743, message: "nao autorizado"))
		#expect(notAuthorized.contains("Automation"))
		// The message is carried for a human and never matched on -- it arrives in
		// the machine's own language.
		#expect(notAuthorized.contains("nao autorizado"))

		#expect(
			VoiceOverFocusInspector.explain(AppleScriptError(number: -600, message: "nao esta rodando"))
				.contains("Command-F5"))
		#expect(
			VoiceOverFocusInspector.explain(AppleScriptError(number: -1728, message: "sem objeto"))
				.contains(ReaderCondition.scriptingChannelDead.rawValue))
	}

	@Test("a cursor read that fails is an error frame, not an empty focus")
	func aFailedCursorReadThrows() {
		let scripts = FakeAppleScriptRunner()
		scripts.failNext(number: -600, message: "not running")
		#expect(throws: FocusError.self) { try inspector(scripts: scripts).focusInfo() }
	}

	@Test("with nothing in front, it answers empty rather than addressing pid 0")
	func nothingInFront() throws {
		let tree = FakeAccessibilityTree(element: button)
		let scripts = FakeAppleScriptRunner()
		scripts.defaultAnswer = "missing value"
		let snapshot = try inspector(
			tree: tree,
			scripts: scripts,
			frontmost: FakeFrontmostApplication(application: nil),
			trust: FakeAccessibilityTrust(trusted: true)
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
