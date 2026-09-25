// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/Registry.swift.

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

	@Test("a session's four, `speech`'s five, input's two, focus, `interact`'s three, guidance")
	func theCommandSet() {
		#expect(
			Set(registry().keys) == [
				"hello", "ping", "echo", "bye",
				"getSpeech", "getLastSpeech", "getNextSpeechIndex",
				"waitForSpeech", "waitForSpeechToFinish",
				"pressGesture", "typeText", "getFocusInfo",
				"announce", "askUser", "waitForUserReply",
				"getGuidance",
			])
	}

	@Test("every key is a command the contract defines -- no invented names")
	func everyKeyIsInTheContract() {
		for name in registry().keys {
			#expect(Command(rawValue: name) != nil, "\(name) is not a command in the contract")
		}
	}

	@Test("it announces all six -- and at 13.11 that is the complete set, not a step")
	func capabilitiesDescribeWhatWorks() {
		#expect(Registry.capabilities == [.speech, .gestures, .typing, .focus, .interact, .guidance])
	}

	@Test("every command an announced capability promises has a handler, and nothing extra")
	func theCapabilityAndItsHandlersAgree() {
		let promised: [Capability: [String]] = [
			.speech: [
				"getSpeech", "getLastSpeech", "getNextSpeechIndex",
				"waitForSpeech", "waitForSpeechToFinish",
			],
			.gestures: ["pressGesture"],
			.typing: ["typeText"],
			.focus: ["getFocusInfo"],
			.interact: ["announce", "askUser", "waitForUserReply"],
			.guidance: ["getGuidance"],
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

	@Test("the two input commands and `askUser` are the ones that move the user's machine")
	func exactlyTheInputCommandsMutateTheReader() {
		let mutating = registry().filter { $0.value.mutatesReader }.keys
		#expect(Set(mutating) == ["pressGesture", "typeText", "askUser"])
	}

	@Test("the reader identity is the one protocol.md's endpoint convention is built from")
	func readerIdentity() {
		let reader = Registry.reader(version: "macOS 15.0.0")
		#expect(reader.name == "voiceover")
		#expect(reader.version == "macOS 15.0.0")
		#expect(defaultEndpointName == reader.name + "McpBridge")
	}
}
