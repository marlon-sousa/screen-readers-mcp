// A hand-written stateful fake for the UtteranceSink port, mirroring
// Sources/CaptureVoice/Domain/Ports/UtteranceSink.swift.
//
// It CONFORMS TO THE PROTOCOL, so a fake that falls behind the port fails to
// compile -- which is Swift's stronger rendering of the Python side's "an ABC
// fails at construction".
//
// It records rather than scripts: the controller's whole job is what it emits and
// in what order, so what a test asserts is the recording.

@testable import CaptureVoice

final class FakeUtteranceSink: UtteranceSink {
	private(set) var events: [CaptureEvent] = []
	/// Called on every emit, so a test can observe the ORDER of an emit relative
	/// to something else -- which is how "text goes out before synthesis starts"
	/// is asserted at all.
	var onEmit: ((CaptureEvent) -> Void)?

	func emit(_ event: CaptureEvent) {
		events.append(event)
		onEmit?(event)
	}

	func events(ofKind kind: CaptureEvent.Kind) -> [CaptureEvent] {
		events.filter { $0.kind == kind }
	}

	/// The one field of the one event of that kind, or nil. Reads better than
	/// three subscripts at every call site.
	func field(_ name: String, ofKind kind: CaptureEvent.Kind) -> FieldValue? {
		events(ofKind: kind).last?.fields[name]
	}
}
