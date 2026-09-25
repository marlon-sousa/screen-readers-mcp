// Mirrors Sources/VoiceOverBridgeAdapters/VoiceOverAdapterFactory.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("VoiceOverAdapterFactory")
struct VoiceOverAdapterFactoryTests {
	@Test("a live session is built, and the set remembers the mode it was built for")
	func liveIsBuilt() throws {
		let set = try testAdapterFactory().build(mode: .live)
		#expect(set.mode == .live)
	}

	@Test("A SILENT SESSION IS BUILT NOW: the marker file is what makes the promise keepable")
	func silentIsBuilt() throws {
		let set = try testAdapterFactory().build(mode: .silent)
		#expect(set.mode == .silent)
	}

	@Test("both modes get the same collaborators, because capture is identical in both")
	func bothModesGetTheSameEdge() throws {
		let factory = testAdapterFactory()
		let live = try factory.build(mode: .live)
		let silent = try factory.build(mode: .silent)
		#expect(live.silenceControl is MarkerFileSilenceControl)
		#expect(silent.silenceControl is MarkerFileSilenceControl)
		#expect(live.speechSource is ContainerFileSpeechSource)
		#expect(silent.speechSource is ContainerFileSpeechSource)
	}

	@Test("both modes get a liveness probe, for the same reason")
	func bothModesGetTheInputEdge() throws {
		let factory = testAdapterFactory()
		for mode in [CaptureMode.live, .silent] {
			let set = try factory.build(mode: mode)
			#expect(set.readerLiveness is VoiceOverLiveness)
		}
	}

	@Test("both modes get a text typer, and the SAME permission broker")
	func bothModesGetTheTypingEdge() throws {
		let permissions = FakePermissionBroker()
		let factory = testAdapterFactory(permissions: permissions)
		for mode in [CaptureMode.live, .silent] {
			let set = try factory.build(mode: mode)
			#expect(set.textTyper is AccessibilityTextTyper)
			#expect(set.permissions === permissions)
		}
	}

	@Test("both modes get the SAME announcer and prompter, and a silent one is not special")
	func bothModesGetTheHumanChannel() throws {
		let announcer = FakeAnnouncer()
		let prompter = FakeUserPrompter()
		let factory = testAdapterFactory(announcer: announcer, prompter: prompter)
		for mode in [CaptureMode.live, .silent] {
			let set = try factory.build(mode: mode)
			#expect(set.announcer === announcer)
			#expect(set.userPrompter === prompter)
		}
	}

	@Test("BUILDING A SESSION ASKS FOR NO PERMISSION -- the request belongs to a COMMAND")
	func buildingAsksForNothing() throws {
		let permissions = FakePermissionBroker()
		_ = try testAdapterFactory(permissions: permissions).build(mode: .live)
		#expect(permissions.requests.isEmpty)
		#expect(permissions.statusReads.isEmpty)
	}

	@Test("a silence control PER SESSION, so one session's teardown cannot lift another's")
	func aSilenceControlPerSession() throws {
		let factory = testAdapterFactory()
		let first = try factory.build(mode: .silent)
		let second = try factory.build(mode: .silent)
		#expect(first.silenceControl !== second.silenceControl)
		#expect(first.speechSource !== second.speechSource)
	}

	@Test("the provider lifecycle is SHARED, because it describes the machine and not the session")
	func theLifecycleIsShared() throws {
		let lifecycle = FakeProviderLifecycle()
		let factory = testAdapterFactory(lifecycle: lifecycle)
		#expect(try factory.build(mode: .live).providerLifecycle === lifecycle)
		#expect(try factory.build(mode: .silent).providerLifecycle === lifecycle)
	}
}
