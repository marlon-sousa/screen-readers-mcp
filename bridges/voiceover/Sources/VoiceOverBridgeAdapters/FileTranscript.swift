// ROLE: adapter -- IMPLEMENTS the Transcript domain port. It owns the
// transcript's VOCABULARY: one timestamped line per event.
//
// DEPENDS ON: the FileWriter seam, never on the filesystem directly. That is
// what makes it precisely testable -- its test asserts the exact lines produced,
// with a fake writer and no disk.
// USED BY: the Session, through the port. BUILT BY: Wiring, via `session(in:)`.
//
// EVERYTHING HERE IS A FORMATTING DECISION, which is why it is an adapter with a
// test and not a leaf. The line shapes match lane 1's, deliberately: a tester
// reading a transcript should not have to learn a second format because the
// reader underneath is a different one.
//
// THE FILE IS THE ONLY RECORD A SILENT RUN LEAVES. Nobody heard it. So events
// outside an open session are dropped rather than buffered -- there is no
// session for a reader to attach them to -- and every write is flushed by the
// leaf, because the tail is exactly what a crash would take.

import Foundation
import VoiceOverBridgeDomain

public final class FileTranscript: Transcript {
	private let writer: any FileWriter
	private let timestamp: () -> String
	private var isOpen = false

	public var logPath: String { writer.path }

	/// `timestamp` is injected so a test gets deterministic lines; the default is
	/// wall-clock, which is what a human reading the file needs.
	public init(writer: any FileWriter, timestamp: @escaping () -> String = FileTranscript.wallclock) {
		self.writer = writer
		self.timestamp = timestamp
	}

	public func open() {
		try? writer.open()
		isOpen = true
	}

	public func sessionOpened(mode: String, voice: String, persona: String) {
		// The persona is written as `-` when absent rather than left out, so every
		// SESSION OPEN line has the same shape: a reader can then tell "no persona
		// was declared" from "this build predates personas" by the field being
		// there at all.
		line("SESSION OPEN mode=\(mode) voice=\(voice) persona=\(persona.isEmpty ? "-" : persona)")
	}

	/// One captured utterance, QUOTED, which is the one place this vocabulary
	/// escapes anything.
	///
	/// The words come from another process and are the only field here a reader
	/// did not choose: a newline in an utterance would otherwise forge a
	/// transcript line, and leading or trailing spaces would be invisible in a
	/// record whose whole job is to say exactly what was said. Lane 1 writes
	/// Python's `repr` for the same reason, and this is the same shape.
	public func speech(_ text: String) {
		line("SPEECH \(FileTranscript.quoted(text))")
	}

	public func gesture(_ command: String) {
		line("GESTURE \(FileTranscript.quoted(command))")
	}

	/// `TYPE length=<n>`, and the number is the whole line ON PURPOSE -- see the
	/// port. Not quoted, because a count cannot forge a transcript line and there
	/// is nothing here that came from another process.
	///
	/// The shape is lane 1's, like every other line in this file: a tester reading
	/// a transcript should not have to learn a second format because the reader
	/// underneath is a different one.
	public func typed(_ length: Int) {
		line("TYPE length=\(length)")
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

	/// `"…"` with backslashes, quotes and newlines escaped, so one utterance is
	/// always one line and always ends where it says it does.
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
	/// Where a session's transcript lives on macOS: the same directory a user is
	/// told to look in for any other application's logs.
	static func defaultLogDirectory(home: String) -> String {
		URL(fileURLWithPath: home).appendingPathComponent("Library/Logs/screen-readers-mcp").path
	}

	/// Compose a transcript over a fresh `session-<stamp>.log`, pruning old ones.
	///
	/// The one place that picks the concrete writer for a real session. `keep`
	/// bounds how many survive, oldest deleted first -- the names embed a
	/// time-sortable stamp, so a lexical sort is a chronological one and, unlike
	/// a modification time, is stable when two files land in the same second.
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
