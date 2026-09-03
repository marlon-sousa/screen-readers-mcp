// ROLE: adapter -- IMPLEMENTS the ChangeJournal domain port. It owns the
// journal's FORMAT: one JSON object per line, appended, never rewritten.
//
// DEPENDS ON: the FileWriter seam, never on the filesystem directly -- which is
// what makes it precisely testable: its test asserts the exact lines produced,
// with a fake writer and no disk. Exactly `FileTranscript`'s shape, for exactly
// `FileTranscript`'s reason.
// BUILT BY: Wiring. USED BY: ReaderEdgeSetup and Session.teardown, through the
// port.
//
// ============================================================================
// JSON LINES, NOT THE TRANSCRIPT'S PROSE, AND THE AUDIENCE IS WHY.
// ============================================================================
//
// The transcript beside this file is written for a HUMAN reading a run
// afterwards, so its lines are prose with a timestamp. This file is written for a
// PROGRAM arriving after a crash -- `scripts/voiceover_restore.py` -- whose job
// is to pair `changed` entries with `restored` ones and act on what is left. A
// format a regular expression has to guess at is a repair tool that mis-parses
// somebody's voice identifier, and the identifier is the thing being repaired.
//
// It stays readable by eye, which matters when the person reading it is the one
// whose reader is wrong: one flat object per line, no nesting, keys in a fixed
// order.
//
// ============================================================================
// ONE FILE FOR THE WHOLE MACHINE, NOT ONE PER SESSION.
// ============================================================================
//
// What a repair needs is EVERY session's unfinished business, and a crashed
// session cannot be relied on to name its own file anywhere a tool will find it.
// So the path is fixed and every session appends to it. The `pid` is on each line
// instead, which is what lets a reader tell two sessions apart -- and, on a
// machine where the accept loop stops being serial, tell a live session's open
// change from a dead one's.
//
// IT IS NEVER PRUNED BY THIS CLASS, unlike the transcripts next to it, and that
// is deliberate rather than an omission: the transcripts are bounded because
// twenty runs of prose is all anybody reads, and this file's whole value is that
// an entry from three weeks ago is still there when somebody finally notices
// their voice is wrong. It grows by a few hundred bytes per session.
//
// EVERY WRITE IS FLUSHED, by the leaf, because the tail is exactly what a crash
// would take -- and a crash is the only reason this file exists.

import Foundation
import VoiceOverBridgeDomain

public final class FileChangeJournal: ChangeJournal {
	/// Where the journal lives, derived from a home directory.
	///
	/// BESIDE THE TRANSCRIPTS, in the directory `hello` already hands the agent a
	/// path into -- so an agent that has a `logPath` has, without being told
	/// anything new, the neighbourhood this file is in. `home` is passed in rather
	/// than read here, like every derivation in this bridge: Wiring is the one
	/// place that reads the environment.
	public static func defaultPath(home: String) -> String {
		URL(fileURLWithPath: FileTranscript.defaultLogDirectory(home: home))
			.appendingPathComponent("reader-changes.jsonl").path
	}

	private let writer: any FileWriter
	private let timestamp: () -> String
	private let pid: Int32

	/// `timestamp` and `pid` are injected so a test gets deterministic lines; the
	/// defaults are wall-clock and this process, which is what a repair tool needs.
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

	/// One line, opening the file if this is the first thing written to it.
	///
	/// OPENED LAZILY, unlike the transcript's explicit `open()`: a session that
	/// changed nothing should leave nothing behind, and most of the value of this
	/// file is that a line in it means something happened.
	private func append(_ change: ReaderChange, restored: Bool) {
		if !isOpen {
			try? writer.open()
			isOpen = true
		}
		writer.writeLine(line(change, restored: restored))
	}

	private var isOpen = false

	/// The line shape, hand-built rather than encoded.
	///
	/// `JSONEncoder` orders keys by whatever it likes, and this file is read by
	/// eye as often as by the script. Six fields, always the same six, always in
	/// this order -- and every value that could contain anything surprising goes
	/// through `quoted`, because a voice identifier comes from a preference file
	/// this bridge did not write.
	private func line(_ change: ReaderChange, restored: Bool) -> String {
		"{\"at\":\(Self.quoted(timestamp())),"
			+ "\"pid\":\(pid),"
			+ "\"change\":\(Self.quoted(change.kind.rawValue)),"
			+ "\"restored\":\(restored ? "true" : "false"),"
			+ "\"store\":\(Self.quoted(change.store)),"
			+ "\"was\":\(Self.quoted(change.was)),"
			+ "\"now\":\(Self.quoted(change.now))}"
	}

	/// A JSON string, or `null`.
	///
	/// NULL IS AN ANSWER AND `""` IS NOT. "There was no previous voice" and "the
	/// previous voice was the empty string" would be indistinguishable if this
	/// collapsed them, and a repair tool acting on the second would write an empty
	/// identifier into somebody's speech preferences.
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

	/// ISO 8601 in UTC, which is what a program reading this wants and what a
	/// human comparing it against a transcript can still line up.
	public static func wallclock() -> String {
		let formatter = ISO8601DateFormatter()
		formatter.timeZone = TimeZone(identifier: "UTC")
		return formatter.string(from: Date())
	}
}
