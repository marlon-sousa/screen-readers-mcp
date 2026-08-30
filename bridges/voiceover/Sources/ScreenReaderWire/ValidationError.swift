// ROLE: entity -- the failure a wire payload that does not fit its shape raises.
// The Swift counterpart of `from_dict`'s ValidationError in the Python binding.
//
// Pure. Thrown by JSONValue's two conversions and by every hand-written
// `init(from:)` that this module's shapes carry; caught by the session (entry
// 13.4), which answers the peer with an `ErrorInfo` carrying its description.
//
// IT NAMES THE FIELD, AND THAT IS THE WHOLE POINT. Swift's DecodingError says
// what went wrong in prose designed for a debugger -- "No value associated with
// key CodingKeys(stringValue: \"mode\")" -- across a codingPath the message does
// not render. A wire fault has to be diagnosable from ONE log line, so this
// flattens the coding path into `HelloParams.mode` exactly as the Python side
// spells it, and keeps the path readable separately from the reason.

import Foundation

public struct ValidationError: Error, Equatable, CustomStringConvertible {
	/// The field that did not fit, as `Shape.field` -- empty when the whole
	/// payload was the problem.
	public let path: String
	/// What was wrong with it.
	public let reason: String

	public var description: String {
		path.isEmpty ? reason : "\(path): \(reason)"
	}

	public init(path: String, reason: String) {
		self.path = path
		self.reason = reason
	}

	/// Translate what a `JSONDecoder` threw while building `type`.
	public init<Value>(decoding type: Value.Type, error: any Error) {
		let shape = String(describing: type)
		guard let decoding = error as? DecodingError else {
			// Not a decoding failure at all: an encoder fault, or a
			// ValidationError a hand-written init already threw. Keep it whole
			// rather than paraphrasing it.
			if let validation = error as? ValidationError {
				self = validation
				return
			}
			self.init(path: shape, reason: String(describing: error))
			return
		}
		switch decoding {
		case .keyNotFound(let key, let context):
			self.init(
				path: ValidationError.path(shape, context.codingPath),
				reason: "missing required field '\(key.stringValue)'"
			)
		case .typeMismatch(let wanted, let context):
			self.init(
				path: ValidationError.path(shape, context.codingPath),
				reason: "expected \(wanted), got something else"
			)
		case .valueNotFound(let wanted, let context):
			self.init(
				path: ValidationError.path(shape, context.codingPath),
				reason: "expected \(wanted), got null"
			)
		case .dataCorrupted(let context):
			self.init(
				path: ValidationError.path(shape, context.codingPath),
				reason: context.debugDescription
			)
		@unknown default:
			self.init(path: shape, reason: String(describing: decoding))
		}
	}

	/// `HelloParams.mode`, or `SpeechResult.entries[0].text` -- the flattening
	/// the DecodingError's own message leaves out.
	static func path(_ shape: String, _ codingPath: [any CodingKey]) -> String {
		var rendered = shape
		for key in codingPath {
			if let index = key.intValue {
				rendered += "[\(index)]"
			} else {
				rendered += ".\(key.stringValue)"
			}
		}
		return rendered
	}
}
