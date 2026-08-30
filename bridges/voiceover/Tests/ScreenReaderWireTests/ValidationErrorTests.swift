// Mirrors Sources/ScreenReaderWire/ValidationError.swift.
//
// The property under test throughout is that ONE LINE is enough to diagnose a
// wire fault: Swift's own DecodingError describes the failure but renders the
// coding path nowhere in its message.

import Testing

@testable import ScreenReaderWire

@Suite("ValidationError")
struct ValidationErrorTests {
	@Test("a missing required field is named, with its shape")
	func missingField() throws {
		let error = try #require(caught(HelloParams.self, #"{"mode":"silent"}"#))
		#expect(error.path == "HelloParams")
		#expect(error.reason == "missing required field 'protocolVersion'")
		#expect(error.description == "HelloParams: missing required field 'protocolVersion'")
	}

	@Test("a field of the wrong type is named at its full path")
	func wrongType() throws {
		let error = try #require(caught(HelloParams.self, #"{"mode":"silent","protocolVersion":"one"}"#))
		#expect(error.path == "HelloParams.protocolVersion")
	}

	@Test("a fault inside an array carries its index, so the entry is findable")
	func insideAnArray() throws {
		let json = #"{"entries":[{"text":"a","index":0,"logPosition":0},{"index":1}],"fromIndex":0,"toIndex":2}"#
		let error = try #require(caught(SpeechResult.self, json))
		#expect(error.path == "SpeechResult.entries[1]")
		#expect(error.reason == "missing required field 'text'")
	}

	@Test("a value outside a closed set says so where it was")
	func closedSet() throws {
		let error = try #require(caught(HelloParams.self, #"{"mode":"whisper","protocolVersion":1}"#))
		#expect(error.path == "HelloParams.mode")
	}

	@Test("a path with no shape prefix renders as the reason alone")
	func bareReason() {
		#expect(ValidationError(path: "", reason: "frame carries neither").description == "frame carries neither")
	}

	private func caught<Value: Decodable>(_ type: Value.Type, _ json: String) -> ValidationError? {
		do {
			_ = try WireJSON.decodeThroughValue(type, json)
			return nil
		} catch let error as ValidationError {
			return error
		} catch {
			return nil
		}
	}
}
