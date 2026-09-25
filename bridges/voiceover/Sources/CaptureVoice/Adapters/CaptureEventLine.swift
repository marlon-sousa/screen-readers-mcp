// ROLE: supporting construct in the adapters layer, the one rendering of a CaptureEvent as a JSON line.
// USED BY: ContainerFileUtteranceSink and OsLogUtteranceSink, which must emit the same bytes.

import Foundation

enum CaptureEventLine {
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
