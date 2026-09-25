// Mirrors Sources/VoiceOverBridgeAdapters/UserDefaultsBridgeConfig.swift.

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
		#expect(defaults.values.count == 5)
	}

	@Test("AN ABSOLUTE PATH IS A LEGAL ENDPOINT NAME, which is what 11.35 decided")
	func aPathIsANameToo() {
		let (settings, _) = config()
		settings.endpointName = "/tmp/some/where.sock"
		#expect(settings.endpointName == "/tmp/some/where.sock")
	}

	@Test("a connection mode this build does not have falls back to the default")
	func anUnknownMode() {
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
		for stored in [0, -1, 70000] {
			let (settings, _) = config(["bridge.loopbackPort": stored])
			#expect(settings.loopbackPort == defaultLoopbackPort, "\(stored) should not be accepted")
		}
	}

	@Test("a value of the wrong TYPE is not propagated either")
	func aHandEditedValue() {
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
