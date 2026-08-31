// Mirrors Sources/VoiceOverBridgeAdapters/UserDefaultsBridgeConfig.swift.
//
// WHAT IS WORTH TESTING IN A SETTINGS ADAPTER is not that a value round-trips --
// it is what happens to a machine that was configured by an older build, or
// edited by hand, or never configured at all. Every read in this file is one of
// those three.
//
// NO TEST HERE WRITES A REAL PREFERENCE: FakeDefaults is an in-memory store, so
// running the suite leaves nothing behind on the developer's machine.

import Fakes
import Testing
import VoiceOverBridgeDomain

@testable import VoiceOverBridgeAdapters

@Suite("UserDefaultsBridgeConfig")
struct UserDefaultsBridgeConfigTests {
	private func config(_ stored: [String: Any] = [:]) -> (UserDefaultsBridgeConfig, FakeDefaults) {
		let defaults = FakeDefaults(stored)
		return (UserDefaultsBridgeConfig(defaults: defaults), defaults)
	}

	@Test("AN UNCONFIGURED MACHINE ANSWERS WITH THE SHIPPED DEFAULTS")
	func unconfigured() {
		let (settings, _) = config()
		#expect(settings.connectionMode == .localEndpoint)
		#expect(settings.endpointName == defaultEndpointName)
		#expect(settings.loopbackPort == defaultLoopbackPort)
		// Attended, because the costs are not symmetric: a machine nobody has
		// configured is not one we may assume is empty (spec 0035).
		#expect(settings.attended)
		#expect(settings.cuesEnabled)
	}

	@Test("what was chosen is what comes back, and it goes to the store immediately")
	func itPersists() {
		let (settings, defaults) = config()
		settings.connectionMode = .loopbackTcp
		settings.endpointName = "someOtherName"
		settings.loopbackPort = 9010
		settings.attended = false
		settings.cuesEnabled = false
		#expect(settings.connectionMode == .loopbackTcp)
		#expect(settings.endpointName == "someOtherName")
		#expect(settings.loopbackPort == 9010)
		#expect(!settings.attended)
		#expect(!settings.cuesEnabled)
		// Straight through, with no cached copy: the dialog writes on the main
		// thread and the accept loop reads on another one.
		#expect(defaults.values.count == 5)
	}

	@Test("AN ABSOLUTE PATH IS A LEGAL ENDPOINT NAME, which is what 11.35 decided")
	func aPathIsANameToo() {
		// On POSIX the same field takes a socket path, and `LocalSocketPath` treats
		// anything with a separator in it as a path the user meant literally. The
		// settings layer does not second-guess that.
		let (settings, _) = config()
		settings.endpointName = "/tmp/some/where.sock"
		#expect(settings.endpointName == "/tmp/some/where.sock")
	}

	@Test("a connection mode this build does not have falls back to the default")
	func anUnknownMode() {
		// A machine configured by an older -- or newer -- build. The shipped default
		// is also what an unconfigured machine gets, so there is one behaviour to
		// reason about rather than two.
		let (settings, _) = config(["bridge.connectionMode": "remoteTcp"])
		#expect(settings.connectionMode == .localEndpoint)
	}

	@Test("an empty endpoint name is not a setting")
	func anEmptyName() {
		let (settings, _) = config(["bridge.endpointName": ""])
		#expect(settings.endpointName == defaultEndpointName)
	}

	@Test("a port outside the legal range falls back rather than failing at bind time")
	func anImpossiblePort() {
		// 0 is excluded on purpose: it means "any free port" to the kernel, which is
		// useless for an endpoint a server has to dial by number.
		for stored in [0, -1, 70000] {
			let (settings, _) = config(["bridge.loopbackPort": stored])
			#expect(settings.loopbackPort == defaultLoopbackPort, "\(stored) should not be accepted")
		}
	}

	@Test("a value of the wrong TYPE is not propagated either")
	func aHandEditedValue() {
		// `defaults write` with a plist literal makes every value a string (spec
		// 0047, finding 17), so this is the shape a hand-edited store arrives in.
		let (settings, _) = config(["bridge.loopbackPort": "9010", "bridge.attended": "false"])
		#expect(settings.loopbackPort == defaultLoopbackPort)
		#expect(settings.attended)
	}

	@Test("READING NEVER REPAIRS THE STORE: opening the dialog edits nobody's settings")
	func readsDoNotWrite() {
		let (settings, defaults) = config(["bridge.connectionMode": "remoteTcp"])
		_ = settings.connectionMode
		_ = settings.endpointName
		_ = settings.loopbackPort
		_ = settings.attended
		_ = settings.cuesEnabled
		#expect(defaults.values as? [String: String] == ["bridge.connectionMode": "remoteTcp"])
	}
}
