// ROLE: entity, the failure a wire payload that does not fit its shape raises.
// It flattens the coding path into `HelloParams.mode`, as the Python binding spells it, so a wire fault
// is diagnosable from one log line.

import Foundation

public struct ValidationError: Error, Equatable, CustomStringConvertible {
	/// Empty when the whole payload was the problem.
	public let path: String
	public let reason: String

	public var description: String {
		path.isEmpty ? reason : "\(path): \(reason)"
	}

	public init(path: String, reason: String) {
		self.path = path
		self.reason = reason
	}

	public init<Value>(decoding type: Value.Type, error: any Error) {
		let shape = String(describing: type)
		guard let decoding = error as? DecodingError else {
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
