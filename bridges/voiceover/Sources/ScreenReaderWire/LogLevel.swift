// ROLE: entity, the reader log verbosity a session may request.

public enum LogLevel: String, Codable, CaseIterable, Sendable {
	case debug
	case io
	case debugwarning
	case info
	case warning
	case error
}
