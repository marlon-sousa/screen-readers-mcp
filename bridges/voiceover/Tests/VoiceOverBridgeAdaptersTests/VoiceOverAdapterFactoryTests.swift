// Mirrors Sources/VoiceOverBridgeAdapters/VoiceOverAdapterFactory.swift.
//
// THE REFUSAL USED TO BE THE TEST, AND 13.6 DELETED IT. Until this entry a
// silent session was refused here, with a named test that said so -- and the
// rule was that whoever made the promise keepable had to delete it in the same
// commit. This file is that deletion.
//
// WHAT REPLACES IT is not "nothing": the refusal MOVED to the handshake, which
// is the only place that can ask whether this machine can actually deliver
// silence. `HelloTests` carries it, named there, and this suite now asserts the
// property that makes the move safe -- both modes get the SAME collaborators, so
// nothing about a mode is decided by which fields happen to be filled in.

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
		// `silent` is a promise about a human's ears -- the reader keeps talking,
		// the human hears nothing, the agent reads what was said. 13.5 could keep
		// only the last clause, so a silent session was refused outright. What
		// changed is the marker this factory now builds: the capture voice reads it
		// once per utterance and renders silence instead of audio, and the lease on
		// it means a dead bridge un-mutes the machine without running any code.
		let set = try testAdapterFactory().build(mode: .silent)
		#expect(set.mode == .silent)
	}

	@Test("both modes get the same collaborators, because capture is identical in both")
	func bothModesGetTheSameEdge() throws {
		// Only RENDERING differs on this route, and the extension does the
		// rendering. A factory that handed a silent session a different set would
		// be inventing a difference the mechanism does not have -- and would put
		// the question "which mode am I?" into every handler.
		let factory = testAdapterFactory()
		let live = try factory.build(mode: .live)
		let silent = try factory.build(mode: .silent)
		#expect(live.silenceControl is MarkerFileSilenceControl)
		#expect(silent.silenceControl is MarkerFileSilenceControl)
		#expect(live.speechSource is ContainerFileSpeechSource)
		#expect(silent.speechSource is ContainerFileSpeechSource)
	}

	@Test("both modes get a gesture sender and a liveness probe, for the same reason")
	func bothModesGetTheInputEdge() throws {
		// A command is dispatched to the reader identically whether or not the
		// human can hear the result -- rendering is the extension's business and
		// the only thing a mode changes on this route.
		let factory = testAdapterFactory()
		for mode in [CaptureMode.live, .silent] {
			let set = try factory.build(mode: mode)
			#expect(set.gestureSender is VoiceOverGestureSender)
			#expect(set.readerLiveness is VoiceOverLiveness)
		}
	}

	@Test("both modes get a text typer, and the SAME permission broker")
	func bothModesGetTheTypingEdge() throws {
		// The typer is per session and stateless, like the gesture sender. The
		// BROKER is shared, because it describes this PROCESS's standing with the
		// system rather than anything about a session -- and because the whole
		// point of 13.8 is that there is exactly one object in the bridge that can
		// ask for the Accessibility grant.
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
		// The channel goes around the reader entirely -- the bridge's own
		// synthesizer, and a window of its own -- so the mode that mutes the reader
		// changes nothing about it. That is exactly why `announce` is audible in a
		// silent session, which is the one mode where it is the human's only
		// channel. Both are SHARED, like the broker: one process has one
		// loudspeaker and one screen.
		let announcer = FakeAnnouncer()
		let prompter = FakeUserPrompter()
		let factory = testAdapterFactory(announcer: announcer, prompter: prompter)
		for mode in [CaptureMode.live, .silent] {
			let set = try factory.build(mode: mode)
			#expect(set.announcer === announcer)
			#expect(set.userPrompter === prompter)
		}
	}

	@Test("BUILDING A SESSION ASKS FOR NO PERMISSION -- the request belongs to `typeText`")
	func buildingAsksForNothing() throws {
		// The structural half of "a session that only presses commands and reads
		// speech never triggers an Accessibility request": the factory runs at
		// every handshake, so a status read or a request here would happen for
		// every session ever established, typing or not.
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
