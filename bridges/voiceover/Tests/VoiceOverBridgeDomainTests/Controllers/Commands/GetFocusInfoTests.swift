// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/GetFocusInfo.swift.
//
// TWO PROPERTIES CARRY THIS FILE, and both are about what the handler does NOT
// do. It never asks the permission broker anything -- the grant is requested
// from exactly one place in this bridge, and adding a second caller would spend
// the lane's one design lever. And it does not interpret the snapshot: `value`
// and `appModule` are optional on the wire so that "the element has no value"
// can be told from "the frame forgot the field", and a handler that helpfully
// turned nil into "" would erase exactly that distinction.

import Fakes
import Foundation
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("GetFocusInfo")
struct GetFocusInfoTests {
	private let handler = GetFocusInfoHandler()

	private func context(
		inspector: FakeFocusInspector = FakeFocusInspector(),
		permissions: FakePermissionBroker = FakePermissionBroker()
	) -> SessionContext {
		let context = SessionContext(
			clock: FakeClock(), transcript: FakeTranscript(), attended: true, close: { _ in })
		context.mode = .live
		context.adapters = fakeAdapterSet(permissions: permissions, focusInspector: inspector)
		return context
	}

	private func result(_ context: SessionContext) throws -> FocusInfoResult {
		let value = try handler.execute(
			context, Request(id: 1, cmd: Command.getFocusInfo.rawValue, params: [:]))
		return try #require(value as? FocusInfoResult)
	}

	@Test("the snapshot reaches the wire field for field")
	func theSnapshotIsReported() throws {
		let inspector = FakeFocusInspector()
		inspector.snapshot = FocusSnapshot(
			name: "Save",
			role: "AXButton",
			states: ["focused", "disabled"],
			value: "on",
			appModule: "com.apple.TextEdit"
		)
		let result = try result(context(inspector: inspector))
		#expect(result.name == "Save")
		#expect(result.role == "AXButton")
		#expect(result.states == ["focused", "disabled"])
		#expect(result.value == "on")
		#expect(result.appModule == "com.apple.TextEdit")
	}

	@Test("NOTHING FOCUSED IS AN EMPTY ANSWER, not an error")
	func anEmptySnapshotIsASuccess() throws {
		// The rule this bridge cannot break: with VoiceOver itself frontmost every
		// read comes back empty and looks exactly like a dead reader (spec 0047,
		// finding 5). An agent checks for "no focus" with the same assertion it
		// uses for "a button is focused", so an empty snapshot must not throw.
		let result = try result(context())
		#expect(result.name.isEmpty)
		#expect(result.role.isEmpty)
		#expect(result.states.isEmpty)
	}

	@Test("a nil `value` stays nil rather than becoming an empty string")
	func theNullableFieldsSurvive() throws {
		// PRESENT AND NULLABLE is the wire's shape for both of these, and the whole
		// reason `FocusInfoResult` writes its own Codable: "the element has no
		// value" is an answer, and "" would be a different one.
		let result = try result(context())
		#expect(result.value == nil)
		#expect(result.appModule == nil)
		let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
		// The KEYS are there, carrying null. A missing key is a broken frame.
		#expect(encoded.contains("\"value\":null"))
		#expect(encoded.contains("\"appModule\":null"))
	}

	@Test("A CHANNEL THAT REFUSED THE QUESTION is an error frame, named")
	func aRefusedChannelFails() {
		let inspector = FakeFocusInspector()
		inspector.failure = FocusError("VoiceOver is not running (-600)")
		#expect(throws: CommandError.self) { try result(context(inspector: inspector)) }
	}

	@Test("ANSWERING FOCUS NEVER TOUCHES THE PERMISSION BROKER -- neither status nor request")
	func focusAsksTheBrokerNothing() throws {
		// 13.8's lever, defended at the one entry that could quietly spend it. The
		// grant is requested from exactly one place in this repository, the
		// TypeText handler, and focus reads whether it is held through an ADAPTER
		// seam -- a question that shows no dialog -- so the domain's broker is not
		// on this path at all. A `status` read here would be harmless today and
		// would put `request` one line away tomorrow.
		let permissions = FakePermissionBroker(state: .notGranted)
		_ = try result(context(permissions: permissions))
		#expect(permissions.requests.isEmpty)
		#expect(permissions.statusReads.isEmpty)
	}

	@Test("focus is read ONCE per command")
	func oneReadPerCommand() throws {
		let inspector = FakeFocusInspector()
		_ = try result(context(inspector: inspector))
		#expect(inspector.reads == 1)
	}

	@Test("it does not move the user's machine, so an observe-only session may ask")
	func itObservesOnly() {
		#expect(handler.mutatesReader == false)
	}

	@Test("read before hello, it fails with a readable error rather than a crash")
	func withoutAReaderEdge() {
		let context = SessionContext(
			clock: FakeClock(), transcript: FakeTranscript(), attended: true, close: { _ in })
		#expect(throws: CommandError.self) { try result(context) }
	}
}
