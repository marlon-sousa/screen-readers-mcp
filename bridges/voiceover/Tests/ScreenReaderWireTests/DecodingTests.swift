// Mirrors Sources/ScreenReaderWire/Decoding.swift.
//
// The whole file exists to keep two absences apart, so these tests are about the
// difference between them -- and about agreeing with the OTHER binding: Python's
// from_dict defaults a missing key and raises on a null in a field that is not
// nullable, and a Swift binding that quietly defaulted both would accept frames
// the NVDA bridge rejects.

import Testing

@testable import ScreenReaderWire

@Suite("Decoding")
struct DecodingTests {
	@Test("a key that was not sent means the contract's default")
	func absentMeansDefault() throws {
		#expect(try WireJSON.decode(PressGestureParams.self, #"{"gestures":[]}"#).graceMs == 100)
	}

	@Test("a key sent as null is a fault, not a request for the default")
	func nullIsAFault() {
		#expect(throws: (any Error).self) {
			try WireJSON.decode(PressGestureParams.self, #"{"gestures":[],"graceMs":null}"#)
		}
	}

	@Test("and the fault names the field, like every other wire fault")
	func nullFaultNamesTheField() throws {
		do {
			_ = try WireJSON.decodeThroughValue(PressGestureParams.self, #"{"gestures":[],"graceMs":null}"#)
			Issue.record("a null graceMs was accepted")
		} catch let error as ValidationError {
			#expect(error.path == "PressGestureParams.graceMs")
			#expect(error.reason.contains("null"))
		}
	}

	@Test("a genuinely nullable field takes both absences as the same answer")
	func nullableFieldsTreatBothAlike() throws {
		// `afterIndex` defaults to null, so "not sent" and "sent as null" say the
		// same thing and decodeIfPresent is the right reading there.
		#expect(try WireJSON.decode(WaitForSpeechParams.self, #"{"text":"a"}"#).afterIndex == nil)
		#expect(try WireJSON.decode(WaitForSpeechParams.self, #"{"text":"a","afterIndex":null}"#).afterIndex == nil)
	}

	@Test("a shape's two defaults agree: the one a caller gets and the one a peer gets")
	func constructedAndDecodedDefaultsAgree() throws {
		// The drift gate reads the PROPERTY declaration, so a contract number that
		// drifted only in the public initialiser would pass it. This is what
		// catches that, and it is why the numbers are spelled twice at all: the
		// initialiser cannot reference the property's own default expression.
		#expect(try PressGestureParams(gestures: []).graceMs
			== WireJSON.decode(PressGestureParams.self, #"{"gestures":[]}"#).graceMs)
		#expect(try TypeParams(text: "").graceMs
			== WireJSON.decode(TypeParams.self, #"{"text":""}"#).graceMs)
		#expect(try WaitForSpeechParams(text: "").timeout
			== WireJSON.decode(WaitForSpeechParams.self, #"{"text":""}"#).timeout)
		#expect(try WaitForUserReplyParams(ticket: "t").timeout
			== WireJSON.decode(WaitForUserReplyParams.self, #"{"ticket":"t"}"#).timeout)
		#expect(try WaitToFinishParams().timeout == WireJSON.decode(WaitToFinishParams.self, "{}").timeout)
		#expect(try GetLogParams().maxEntries == WireJSON.decode(GetLogParams.self, "{}").maxEntries)
		#expect(try GetLogParams().windows == WireJSON.decode(GetLogParams.self, "{}").windows)
		#expect(try WaitForLogParams().timeout == WireJSON.decode(WaitForLogParams.self, "{}").timeout)
		#expect(try AckResult().ok == WireJSON.decode(AckResult.self, "{}").ok)
		#expect(try PingResult().ok == WireJSON.decode(PingResult.self, "{}").ok)
	}

	@Test("and a bridge version nobody set is the contract's own placeholder either way")
	func helloResultDefaultsAgree() throws {
		let constructed = HelloResult(
			protocolVersion: 1,
			reader: ReaderInfo(name: "VoiceOver", version: "15.0"),
			capabilities: [],
			mode: .silent,
			synth: "Capture Voice",
			logPath: "/tmp/x"
		)
		let json = """
		{"protocolVersion":1,"reader":{"name":"VoiceOver","version":"15.0"},"capabilities":[],\
		"mode":"silent","synth":"Capture Voice","logPath":"/tmp/x"}
		"""
		#expect(try constructed == WireJSON.decode(HelloResult.self, json))
	}

	@Test("a request whose params are null is refused, as the Python binding refuses it")
	func nullParamsAreRefused() {
		#expect(throws: (any Error).self) {
			try WireJSON.decode(Request.self, #"{"id":1,"cmd":"ping","params":null}"#)
		}
	}
}
