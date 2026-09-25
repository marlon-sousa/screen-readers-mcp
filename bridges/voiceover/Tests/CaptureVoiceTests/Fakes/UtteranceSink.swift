@testable import CaptureVoice

final class FakeUtteranceSink: UtteranceSink {
	private(set) var events: [CaptureEvent] = []
	var onEmit: ((CaptureEvent) -> Void)?

	func emit(_ event: CaptureEvent) {
		events.append(event)
		onEmit?(event)
	}

	func events(ofKind kind: CaptureEvent.Kind) -> [CaptureEvent] {
		events.filter { $0.kind == kind }
	}

	func field(_ name: String, ofKind kind: CaptureEvent.Kind) -> FieldValue? {
		events(ofKind: kind).last?.fields[name]
	}
}
