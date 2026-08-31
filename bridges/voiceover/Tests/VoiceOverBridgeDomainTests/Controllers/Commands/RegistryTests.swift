// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/Registry.swift.
//
// THE ENUMERATION TESTS ARE THE POINT OF THIS FILE. The registry is where a
// handler is connected and where this bridge states what it can do, so the
// assertions are about the SET -- which commands are served, which capabilities
// are announced, and which handler carries a flag the dispatch loop reads. A
// handler added without a capability, or a capability announced without a
// handler, is exactly the mistake the capability gate exists to prevent, and it
// is invisible in any single handler's own test.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("Registry")
struct RegistryTests {
	private func registry() -> [String: any CommandHandler] {
		Registry.build(
			factory: FakeAdapterFactory(), readerVersion: "macOS 15.0.0", bridgeVersion: "1.2.3"
		)
	}

	@Test("it serves a session's four, `speech`'s five, both halves of input, and focus")
	func theCommandSet() {
		#expect(
			Set(registry().keys) == [
				"hello", "ping", "echo", "bye",
				"getSpeech", "getLastSpeech", "getNextSpeechIndex",
				"waitForSpeech", "waitForSpeechToFinish",
				"pressGesture", "typeText", "getFocusInfo",
			])
	}

	@Test("every key is a command the contract defines -- no invented names")
	func everyKeyIsInTheContract() {
		for name in registry().keys {
			#expect(Command(rawValue: name) != nil, "\(name) is not a command in the contract")
		}
	}

	@Test("it announces `speech`, `gestures`, `typing` and `focus` -- what this build serves")
	func capabilitiesDescribeWhatWorks() {
		#expect(Registry.capabilities == [.speech, .gestures, .typing, .focus])
	}

	@Test("every command an announced capability promises has a handler, and nothing extra")
	func theCapabilityAndItsHandlersAgree() {
		// THE MISTAKE THIS CATCHES is invisible in any single handler's test: a
		// capability announced with one of its commands missing is a tool the
		// agent can see, call, and get "unknown command" from. protocol.md §5
		// lists what each capability covers; this is that list.
		let promised: [Capability: [String]] = [
			.speech: [
				"getSpeech", "getLastSpeech", "getNextSpeechIndex",
				"waitForSpeech", "waitForSpeechToFinish",
			],
			.gestures: ["pressGesture"],
			// A SEPARATE CAPABILITY FROM `gestures`, AND THAT IS THE DESIGN. The two
			// halves of input cost different permissions on macOS (spec 0041), so an
			// agent has to be able to be told that one of them works on this machine
			// and the other does not. Folding them into one string would make that
			// unsayable.
			.typing: ["typeText"],
			// ANNOUNCED WITHOUT A PERMISSION BEHIND IT. Focus answers richer where
			// typing's Accessibility grant is already held and thinner where it is
			// not -- one capability either way, because the command works on every
			// machine and the wire has no shape for "works better over there".
			.focus: ["getFocusInfo"],
		]
		let served = registry()
		for (capability, commands) in promised {
			#expect(Registry.capabilities.contains(capability))
			for command in commands {
				#expect(
					served[command] != nil,
					"`\(capability.rawValue)` promises \(command) and nothing serves it")
			}
		}
		// AND THE CONVERSE, which is the half that would otherwise rot: nothing is
		// announced that this table does not account for, so a capability added to
		// `Registry.capabilities` without its handlers fails HERE rather than in a
		// live session.
		#expect(Set(Registry.capabilities) == Set(promised.keys))
	}

	@Test("hello is the only command legal before the handshake")
	func onlyHelloIsAvailableBeforeHello() {
		let available = registry().filter { $0.value.availableBeforeHello }.keys
		#expect(Set(available) == ["hello"])
	}

	@Test("ping is the only command that does not reset the inactivity watchdog")
	func onlyPingSkipsInactivity() {
		let passive = registry().filter { !$0.value.resetsInactivity }.keys
		#expect(Set(passive) == ["ping"])
	}

	@Test("the two input commands are STILL the only ones that move the user's machine")
	func exactlyTheInputCommandsMutateTheReader() {
		// THE FLAG DEFAULTS TO `false` AND THE FAILURE MODE OF FORGETTING IS
		// "ALLOWED", so a new mutating handler that omits it is invisible in its
		// own test and visible only here. This assertion is the SET rather than a
		// membership check for exactly that reason -- and it did its job at 13.8:
		// it FAILED the moment `typeText` was registered, which is the test asking
		// whether the new handler had opted in, and the fix was to state the new
		// set rather than to weaken the assertion. 13.9 adds a handler and does NOT
		// join this set: reading where the focus is moves nothing, which is what
		// lets an observe-only session (spec 0017) ask.
		let mutating = registry().filter { $0.value.mutatesReader }.keys
		#expect(Set(mutating) == ["pressGesture", "typeText"])
	}

	@Test("the reader identity is the one protocol.md's endpoint convention is built from")
	func readerIdentity() {
		let reader = Registry.reader(version: "macOS 15.0.0")
		#expect(reader.name == "voiceover")
		#expect(reader.version == "macOS 15.0.0")
		// The convention: <reader>McpBridge. Asserted here, beside the name it is
		// built from, because the two drifting apart is what would leave a shipped
		// default endpoint pointing at nothing.
		#expect(defaultEndpointName == reader.name + "McpBridge")
	}
}
