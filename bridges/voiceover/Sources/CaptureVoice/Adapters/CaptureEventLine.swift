// ROLE: supporting construct in the adapters layer -- the ONE rendering of a
// CaptureEvent as a JSON line.
//
// Used by ContainerFileUtteranceSink (which appends it to the container file the
// bridge reads) and by OsLogUtteranceSink (which logs the same bytes). It is one
// file rather than a method on each sink because the two routes emitting the
// SAME line is the property that makes them interchangeable when one of them is
// denied by the sandbox -- and a property held by two copies of a function is a
// property that lasts until somebody edits one of them.
//
// AMENDMENT TO SPEC 0046's 13.2 LAYOUT, with its why: the spec lists the two
// sinks and no shared renderer, because in the spike the rendering lived in the
// one `note()` both routes went through. Splitting the sinks split that; this
// puts it back, as a pure function with a test, rather than duplicating it.
//
// It is NOT in the domain. JSON is a wire vocabulary and the domain speaks
// FieldValue -- the same reason JSON-lines framing is an adapter in the NVDA
// bridge even though it is pure.

import Foundation

enum CaptureEventLine {
	/// Sorted keys, deliberately: the feed is read by a human with `tail -f` as
	/// often as by the bridge, and a stable field order is what makes two
	/// consecutive utterances comparable at a glance.
	///
	/// Returns a self-describing line even when encoding fails, because a sink
	/// that silently emits nothing is indistinguishable from a reader that said
	/// nothing.
	static func json(_ event: CaptureEvent, at instant: Double) -> String {
		var object: [String: Any] = ["event": event.kind.rawValue, "at": instant]
		for (name, value) in event.fields {
			switch value {
			case .text(let text): object[name] = text
			case .count(let count): object[name] = count
			case .number(let number): object[name] = number
			case .flag(let flag): object[name] = flag
			}
		}
		guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
			let text = String(data: data, encoding: .utf8)
		else {
			return "{\"event\":\"encode-failed\",\"kind\":\"\(event.kind.rawValue)\"}"
		}
		return text
	}
}
