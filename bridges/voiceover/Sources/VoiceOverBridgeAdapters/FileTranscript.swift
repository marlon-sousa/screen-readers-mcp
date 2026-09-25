// ROLE: adapter implementing the Transcript port; it owns the transcript's vocabulary, one timestamped line per event.
// USED BY: the Session, through the port. BUILT BY: Wiring, via `session(in:)`.
// Line shapes match the NVDA bridge's transcript, so a tester reads one format for both readers.

import Foundation
import VoiceOverBridgeDomain

public final class FileTranscript: Transcript {
	private let writer: any FileWriter
	private let timestamp: () -> String
	private var isOpen = false

	public var logPath: String { writer.path }

	public init(writer: any FileWriter, timestamp: @escaping () -> String = FileTranscript.wallclock) {
		self.writer = writer
		self.timestamp = timestamp
	}

	public func open() {
		try? writer.open()
		isOpen = true
	}

	public func sessionOpened(mode: String, voice: String, persona: String) {
		// `-` when absent, so every SESSION OPEN line carries the same fields.
		line("SESSION OPEN mode=\(mode) voice=\(voice) persona=\(persona.isEmpty ? "-" : persona)")
	}

	/// Quoted: the words come from another process, and an unescaped newline would forge a transcript line.
	public func speech(_ text: String) {
		line("SPEECH \(FileTranscript.quoted(text))")
	}

	public func gesture(_ command: String) {
		line("GESTURE \(FileTranscript.quoted(command))")
	}

	/// Only the length is recorded, never the typed text.
	public func typed(_ length: Int) {
		line("TYPE length=\(length)")
	}

	public func announced(_ text: String) {
		line("ANNOUNCE \(FileTranscript.quoted(text))")
	}

	public func note(_ text: String) {
		line("NOTE \(text)")
	}

	public func sessionClosed(reason: String) {
		line("SESSION CLOSE reason=\(reason)")
		isOpen = false
		writer.close()
	}

	private func line(_ text: String) {
		guard isOpen else { return }
		writer.writeLine("\(timestamp()) \(text)")
	}

	static func quoted(_ text: String) -> String {
		let escaped =
			text
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
			.replacingOccurrences(of: "\n", with: "\\n")
			.replacingOccurrences(of: "\r", with: "\\r")
		return "\"\(escaped)\""
	}

	public static func wallclock() -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
		return formatter.string(from: Date())
	}
}

public extension FileTranscript {
	static func defaultLogDirectory(home: String) -> String {
		URL(fileURLWithPath: home).appendingPathComponent("Library/Logs/screen-readers-mcp").path
	}

	/// Keeps the newest `keep` transcripts; the stamp in each name sorts lexically in time order.
	static func session(in directory: String, keep: Int = 20, stamp: String? = nil) -> FileTranscript {
		let manager = FileManager.default
		try? manager.createDirectory(atPath: directory, withIntermediateDirectories: true)
		let name = stamp ?? {
			let formatter = DateFormatter()
			formatter.locale = Locale(identifier: "en_US_POSIX")
			formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
			return formatter.string(from: Date())
		}()
		let existing = ((try? manager.contentsOfDirectory(atPath: directory)) ?? [])
			.filter { $0.hasPrefix("session-") && $0.hasSuffix(".log") }
			.sorted()
		for stale in existing.dropLast(max(0, keep - 1)) {
			try? manager.removeItem(atPath: URL(fileURLWithPath: directory).appendingPathComponent(stale).path)
		}
		return FileTranscript(
			writer: TextFileWriter(
				path: URL(fileURLWithPath: directory).appendingPathComponent("session-\(name).log").path
			)
		)
	}
}
