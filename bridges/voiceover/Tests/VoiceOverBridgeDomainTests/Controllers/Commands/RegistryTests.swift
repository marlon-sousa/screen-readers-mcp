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

	@Test("it serves the four a session needs, plus the five `speech` promises")
	func theCommandSet() {
		#expect(
			Set(registry().keys) == [
				"hello", "ping", "echo", "bye",
				"getSpeech", "getLastSpeech", "getNextSpeechIndex",
				"waitForSpeech", "waitForSpeechToFinish",
			])
	}

	@Test("every key is a command the contract defines -- no invented names")
	func everyKeyIsInTheContract() {
		for name in registry().keys {
			#expect(Command(rawValue: name) != nil, "\(name) is not a command in the contract")
		}
	}

	@Test("it announces `speech` and nothing else, because that is what this build serves")
	func capabilitiesDescribeWhatWorks() {
		#expect(Registry.capabilities == [.speech])
	}

	@Test("every command `speech` promises has a handler, and no handler is announced twice")
	func theCapabilityAndItsHandlersAgree() {
		// THE MISTAKE THIS CATCHES is invisible in any single handler's test: a
		// capability announced with one of its commands missing is a tool the
		// agent can see, call, and get "unknown command" from. protocol.md §5
		// lists what `speech` covers; this is that list.
		let promised = [
			"getSpeech", "getLastSpeech", "getNextSpeechIndex",
			"waitForSpeech", "waitForSpeechToFinish",
		]
		let served = registry()
		#expect(Registry.capabilities.contains(.speech))
		for command in promised {
			#expect(served[command] != nil, "`speech` promises \(command) and nothing serves it")
		}
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

	@Test("nothing here moves the user's machine; the input entries are the first that will")
	func nothingMutatesTheReaderYet() {
		#expect(registry().values.allSatisfy { !$0.mutatesReader })
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
