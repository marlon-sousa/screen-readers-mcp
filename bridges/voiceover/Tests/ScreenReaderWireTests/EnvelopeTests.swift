// Mirrors Sources/ScreenReaderWire/Envelope.swift.
//
// Two of these are interop assertions rather than Swift ones: an unknown command
// must survive decoding, and an error frame from the PYTHON bridge carries both
// `result: null` and `error`, because its to_dict renders every field.

import Testing

@testable import ScreenReaderWire

@Suite("Envelope")
struct EnvelopeTests {
	@Test("a request with no params decodes with an empty params object")
	func paramsDefaultToEmpty() throws {
		let request = try WireJSON.decode(Request.self, #"{"id":1,"cmd":"ping"}"#)
		#expect(request.params.isEmpty)
	}

	@Test("an unknown command decodes cleanly, because cmd is a raw string")
	func unknownCommandIsData() throws {
		let request = try WireJSON.decode(Request.self, #"{"id":2,"cmd":"makeCoffee"}"#)
		#expect(request.cmd == "makeCoffee")
		#expect(Command(rawValue: request.cmd) == nil)
	}

	@Test("params are read as the command's own shape")
	func paramsAsATypedShape() throws {
		let request = try WireJSON.decode(
			Request.self,
			#"{"id":3,"cmd":"pressGesture","params":{"gestures":["kb:tab"]}}"#
		)
		let params = try request.params(as: PressGestureParams.self)
		#expect(params.gestures == ["kb:tab"])
		#expect(params.graceMs == 100)
	}

	@Test("params that do not fit the shape raise a ValidationError naming the field")
	func paramsThatDoNotFit() throws {
		let request = try WireJSON.decode(Request.self, #"{"id":4,"cmd":"pressGesture","params":{}}"#)
		#expect(throws: ValidationError.self) {
			try request.params(as: PressGestureParams.self)
		}
	}

	@Test("a success frame carries the result and no error key at all")
	func successFrame() throws {
		let response = try Response.succeeded(id: 5, with: AckResult())
		#expect(try WireJSON.keys(of: response) == ["id", "result"])
		#expect(try response.outcome() == .success(.object(["ok": .bool(true)])))
	}

	@Test("a failure frame carries the error and leaves the result out")
	func failureFrame() throws {
		let response = Response.failed(id: 6, message: "unknown command 'makeCoffee'")
		#expect(try WireJSON.keys(of: response) == ["error", "id"])
		#expect(try response.outcome() == .failure(ErrorInfo(message: "unknown command 'makeCoffee'")))
	}

	@Test("the Python bridge's error frame -- both keys present -- reads as a failure")
	func pythonErrorFrameCarriesBothKeys() throws {
		// Measured, not assumed: dataclasses.asdict renders every field, so an
		// NVDA-bridge failure arrives with an explicit null result beside it.
		let response = try WireJSON.decode(Response.self, #"{"id":7,"result":null,"error":{"message":"nope"}}"#)
		#expect(try response.outcome() == .failure(ErrorInfo(message: "nope")))
	}

	@Test("a frame carrying neither is refused rather than read as an empty success")
	func neitherIsAFault() throws {
		let response = try WireJSON.decode(Response.self, #"{"id":8}"#)
		#expect(throws: ValidationError.self) {
			try response.outcome()
		}
	}

	@Test("a result that is genuinely null is a success, not a fault")
	func explicitNullResultIsASuccess() throws {
		let response = try WireJSON.decode(Response.self, #"{"id":9,"result":null}"#)
		#expect(try response.outcome() == .success(.null))
	}
}
