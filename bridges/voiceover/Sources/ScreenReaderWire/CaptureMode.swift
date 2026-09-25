// ROLE: entity, the speech-capture mode a session chooses at `hello` time.

public enum CaptureMode: String, Codable, CaseIterable, Sendable {
	case silent
	case live
}
