// ROLE: adapter implementing the ChangeJournal port; it owns the journal's format, one JSON object per line, appended and never rewritten.
// BUILT BY: Wiring.
// USED BY: ReaderEdgeSetup and Session.teardown, through the port.
// `scripts/voiceover_restore.py` parses this format to pair `changed` with `restored` entries, so keep its keys and their order stable.
// Never pruned: an unrestored entry must survive until somebody notices their voice is wrong.

import Foundation
import VoiceOverBridgeDomain

public final class FileChangeJournal: ChangeJournal {
	public static func defaultPath(home: String) -> String {
		URL(fileURLWithPath: FileTranscript.defaultLogDirectory(home: home))
			.appendingPathComponent("reader-changes.jsonl").path
	}

	private let writer: any FileWriter
	private let timestamp: () -> String
	private let pid: Int32

	public init(
		writer: any FileWriter,
		timestamp: @escaping () -> String = FileChangeJournal.wallclock,
		pid: Int32 = ProcessInfo.processInfo.processIdentifier
	) {
		self.writer = writer
		self.timestamp = timestamp
		self.pid = pid
	}

	public var path: String { writer.path }

	public func changed(_ change: ReaderChange) {
		append(change, restored: false)
	}

	public func restored(_ change: ReaderChange) {
		append(change, restored: true)
	}

	// -- the format ------------------------------------------------------------

	private func append(_ change: ReaderChange, restored: Bool) {
		if !isOpen {
			try? writer.open()
			isOpen = true
		}
		writer.writeLine(line(change, restored: restored))
	}

	private var isOpen = false

	private func line(_ change: ReaderChange, restored: Bool) -> String {
		"{\"at\":\(Self.quoted(timestamp())),"
			+ "\"pid\":\(pid),"
			+ "\"change\":\(Self.quoted(change.kind.rawValue)),"
			+ "\"restored\":\(restored ? "true" : "false"),"
			+ "\"store\":\(Self.quoted(change.store)),"
			+ "\"was\":\(Self.quoted(change.was)),"
			+ "\"now\":\(Self.quoted(change.now))}"
	}

	/// Nil becomes `null`, never `""`, or a repair tool would write an empty identifier into the user's speech preferences.
	static func quoted(_ text: String?) -> String {
		guard let text else { return "null" }
		var out = "\""
		for character in text.unicodeScalars {
			switch character {
			case "\"": out += "\\\""
			case "\\": out += "\\\\"
			case "\n": out += "\\n"
			case "\r": out += "\\r"
			case "\t": out += "\\t"
			default:
				if character.value < 0x20 {
					out += String(format: "\\u%04x", character.value)
				} else {
					out.unicodeScalars.append(character)
				}
			}
		}
		return out + "\""
	}

	public static func wallclock() -> String {
		let formatter = ISO8601DateFormatter()
		formatter.timeZone = TimeZone(identifier: "UTC")
		return formatter.string(from: Date())
	}
}
