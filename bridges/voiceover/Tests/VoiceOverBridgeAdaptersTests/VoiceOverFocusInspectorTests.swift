// Mirrors Sources/VoiceOverBridgeAdapters/VoiceOverFocusInspector.swift.

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

	@Test("it reads the accessibility tree, addressed to the frontmost pid")
	func theTreeRouteAnswers() throws {
		let tree = FakeAccessibilityTree(element: button)
		let snapshot = try inspector(tree: tree).focusInfo()

		#expect(snapshot.name == "Save")
		#expect(snapshot.role == "AXButton")
		#expect(tree.queries.map(\.pid) == [4242])
	}

	@Test("A REVOKED GRANT IS A NAMED FAILURE, never an empty snapshot")
	func aRevokedGrantIsNamed() {
		let tree = FakeAccessibilityTree(element: button)
		#expect(throws: FocusError.self) {
			try inspector(tree: tree, trust: FakeAccessibilityTrust(trusted: false)).focusInfo()
		}
		#expect(tree.queries.isEmpty)
	}

	@Test("the grant is READ, never requested, and read once per call")
	func theTrustSeamIsOnlyRead() throws {
		let trust = FakeAccessibilityTrust(trusted: true)
		_ = try inspector(tree: FakeAccessibilityTree(element: button), trust: trust).focusInfo()
		#expect(trust.reads == 1)
	}

	@Test("A READ WITH NOTHING FOCUSED ANSWERS EMPTY, and reaches for nothing else")
	func thereIsNoFallbackBetweenRoutes() throws {
		let snapshot = try inspector(tree: FakeAccessibilityTree(element: nil)).focusInfo()
		#expect(snapshot.name.isEmpty)
	}

	@Test("the query names AXRole and never AXRoleDescription, which is the localized one")
	func theAttributeQuery() throws {
		let tree = FakeAccessibilityTree(element: button)
		_ = try inspector(tree: tree, trust: FakeAccessibilityTrust(trusted: true)).focusInfo()
		let asked = try #require(tree.queries.first).attributes
		#expect(asked.contains("AXRole"))
		#expect(asked.contains("AXTitle"))
		#expect(asked.contains("AXDescription"))
		#expect(asked.contains("AXValue"))
		#expect(!asked.contains("AXRoleDescription"))
	}

	@Test("AXTitle wins over AXDescription, and an element with neither has no name")
	func theNamePreference() {
		#expect(
			VoiceOverFocusInspector.name(from: ["AXTitle": .text("Save"), "AXDescription": .text("Store")])
				== "Save")
		#expect(VoiceOverFocusInspector.name(from: ["AXDescription": .text("Store")]) == "Store")
		#expect(VoiceOverFocusInspector.name(from: ["AXRole": .text("AXButton")]).isEmpty)
	}

	@Test("states come from BOOLEANS, and only when the attribute is there")
	func theStates() {
		#expect(
			VoiceOverFocusInspector.states(from: [
				"AXFocused": .flag(true), "AXSelected": .flag(true), "AXEnabled": .flag(false),
			]) == ["focused", "selected", "disabled"])
		#expect(VoiceOverFocusInspector.states(from: ["AXEnabled": .flag(true)]).isEmpty)
		#expect(VoiceOverFocusInspector.states(from: ["AXFocused": .flag(false)]).isEmpty)
		#expect(VoiceOverFocusInspector.states(from: [:]).isEmpty)
	}

	@Test("`value` renders text, flags and numbers -- and a whole number keeps no decimal point")
	func theValueRendering() {
		#expect(VoiceOverFocusInspector.rendered(.text("on")) == "on")
		#expect(VoiceOverFocusInspector.rendered(.flag(true)) == "true")
		#expect(VoiceOverFocusInspector.rendered(.number(1)) == "1")
		#expect(VoiceOverFocusInspector.rendered(.number(0.5)) == "0.5")
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

	@Test("NOTHING FOCUSED IS AN ANSWER, and `appModule` still arrives")
	func nothingFocusedIsNotAFault() throws {
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
