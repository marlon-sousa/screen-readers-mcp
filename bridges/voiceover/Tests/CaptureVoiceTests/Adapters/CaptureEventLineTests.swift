// Mirrors Sources/CaptureVoice/Adapters/CaptureEventLine.swift.
//
// The two sinks emit the SAME bytes, which is what makes them interchangeable
// when the sandbox denies one of them. This is the file that keeps that true.
//
// It is also the wire the bridge reads (entry 13.5), so the field names and the
// shape are a contract and not a rendering preference.

import Foundation
import Testing

@testable import CaptureVoice

@Suite("CaptureEventLine")
struct CaptureEventLineTests {
	func decode(_ line: String) -> [String: Any] {
		let data = Data(line.utf8)
		return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
	}

	@Test("the event kind and the instant are always there")
	func envelopeIsAlwaysPresent() {
		let line = CaptureEventLine.json(CaptureEvent(kind: .synthesize, fields: [:]), at: 1_724_900_000.5)
		let object = decode(line)
		#expect(object["event"] as? String == "synthesize")
		#expect(object["at"] as? Double == 1_724_900_000.5)
	}

	@Test("every field kind renders as its own JSON type")
	func fieldKindsRenderFaithfully() {
		let line = CaptureEventLine.json(
			CaptureEvent(
				kind: .cancel,
				fields: [
					"ssml": .text("<speak>um</speak>"),
					"seq": .count(3),
					"source_rate": .number(22050),
					"silent": .flag(true),
				]),
			at: 0)
		let object = decode(line)
		#expect(object["ssml"] as? String == "<speak>um</speak>")
		#expect(object["seq"] as? Int == 3)
		#expect(object["source_rate"] as? Double == 22050)
		#expect(object["silent"] as? Bool == true)
	}

	@Test("keys are sorted, so two lines can be compared by eye")
	func keysAreSorted() {
		let line = CaptureEventLine.json(
			CaptureEvent(kind: .synthesize, fields: ["zebra": .count(1), "alpha": .count(2)]), at: 0)
		#expect(line.range(of: "\"alpha\"")!.lowerBound < line.range(of: "\"zebra\"")!.lowerBound)
		#expect(line.range(of: "\"at\"")!.lowerBound < line.range(of: "\"event\"")!.lowerBound)
	}

	@Test("the kind names are the ones the bridge parses")
	func kindNamesAreTheContract() {
		#expect(CaptureEvent.Kind.audioUnitCreated.rawValue == "audio-unit-created")
		#expect(CaptureEvent.Kind.allocateRenderResources.rawValue == "allocate-render-resources")
		#expect(CaptureEvent.Kind.speechVoicesRead.rawValue == "speech-voices-read")
		#expect(CaptureEvent.Kind.synthesize.rawValue == "synthesize")
		#expect(CaptureEvent.Kind.cancel.rawValue == "cancel")
	}

	@Test("one line, and no embedded newline can break the framing")
	func theLineIsOneLine() {
		let line = CaptureEventLine.json(
			CaptureEvent(kind: .synthesize, fields: ["text": .text("um\ndois")]), at: 0)
		#expect(!line.contains("\n"))
		#expect(decode(line)["text"] as? String == "um\ndois")
	}
}
