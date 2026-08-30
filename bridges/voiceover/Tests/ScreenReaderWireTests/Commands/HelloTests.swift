// Mirrors Sources/ScreenReaderWire/Commands/Hello.swift.

import Testing

@testable import ScreenReaderWire

@Suite("hello")
struct HelloTests {
	@Test("the minimum handshake a peer can send is a mode and a version")
	func minimalParams() throws {
		let params = try WireJSON.decode(HelloParams.self, #"{"mode":"silent","protocolVersion":1}"#)
		#expect(params.mode == .silent)
		#expect(params.protocolVersion == ProtocolVersion.current)
		#expect(params.logLevel == nil)
		#expect(params.normalize == nil)
		#expect(params.persona.isEmpty)
	}

	@Test("`normalize` unset is not `normalize` false -- it means the mode's own default")
	func normalizeIsThreeValued() throws {
		let unset = try WireJSON.decode(HelloParams.self, #"{"mode":"live","protocolVersion":1}"#)
		let refused = try WireJSON.decode(HelloParams.self, #"{"mode":"live","protocolVersion":1,"normalize":false}"#)
		#expect(unset.normalize == nil)
		#expect(refused.normalize == false)
	}

	@Test("a handshake without a version is refused rather than defaulted")
	func versionIsRequired() {
		// Defaulting it would let a mismatched pair connect and fail later, which
		// is the failure the handshake exists to prevent.
		#expect(throws: (any Error).self) {
			try WireJSON.decode(HelloParams.self, #"{"mode":"silent"}"#)
		}
	}

	@Test("the result a bridge with no guidance and no silence cap sends still decodes")
	func minimalResult() throws {
		let json = """
		{"protocolVersion":1,"reader":{"name":"VoiceOver","version":"15.0"},"capabilities":["speech"],\
		"mode":"silent","synth":"Capture Voice","logPath":"/tmp/session.log"}
		"""
		let result = try WireJSON.decode(HelloResult.self, json)
		#expect(result.reader == ReaderInfo(name: "VoiceOver", version: "15.0"))
		#expect(result.bridgeVersion == "unknown")
		#expect(result.guidance == nil)
		#expect(result.silenceCap == nil)
		#expect(result.attended == nil)
		#expect(result.normalized.isEmpty)
	}

	@Test("a capability this build has never heard of survives the handshake")
	func unknownCapabilityDoesNotBreakTheHandshake() throws {
		let json = """
		{"protocolVersion":1,"reader":{"name":"JAWS","version":"2026"},"capabilities":["speech","telepathy"],\
		"mode":"live","synth":"Eloquence","logPath":"C:\\\\log.txt"}
		"""
		let result = try WireJSON.decode(HelloResult.self, json)
		#expect(result.capabilities.count == 2)
		#expect(result.capabilities.contains(Capability(rawValue: "telepathy")))
	}

	@Test("a full result round-trips, silence cap and normalizations included")
	func fullResultRoundTrips() throws {
		let result = HelloResult(
			protocolVersion: ProtocolVersion.current,
			reader: ReaderInfo(name: "VoiceOver", version: "15.0"),
			capabilities: [.speech, .gestures, .typing, .focus, .interact, .guidance],
			mode: .silent,
			synth: "Capture Voice",
			logPath: "/tmp/session.log",
			bridgeVersion: "0.1.0",
			guidance: GetGuidanceResult(persona: "tester", recognised: true, text: "read this"),
			silenceCap: SilenceCapInfo(enabled: true, warnAfterSeconds: 30, liftAfterSeconds: 120),
			attended: true,
			normalized: [
				NormalizedSetting(keyPath: ["speech", "rate"], previous: .int(60), current: .int(50), why: "steadier")
			]
		)
		#expect(try WireJSON.roundTrip(result) == result)
	}

	@Test("a normalized setting carries whatever the reader's own value was")
	func normalizedValuesAreOpen() throws {
		let json = """
		{"keyPath":["a","b"],"previous":{"nested":[1,null]},"current":"plain","why":"because"}
		"""
		let setting = try WireJSON.decode(NormalizedSetting.self, json)
		#expect(setting.previous == .object(["nested": .array([.int(1), .null])]))
		#expect(setting.current == .string("plain"))
	}
}
