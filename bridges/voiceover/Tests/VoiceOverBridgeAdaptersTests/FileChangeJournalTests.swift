// Mirrors Sources/VoiceOverBridgeAdapters/FileChangeJournal.swift.
//
// THE FORMAT IS THE CONTRACT, because the reader is a program: this file's whole
// audience is `scripts/voiceover_restore.py` and a human arriving after a crash,
// and what they do is pair `changed` entries with `restored` ones. So the tests
// assert the exact bytes -- one flat JSON object per line, the same six keys in
// the same order -- rather than "something was written".
//
// The escaping tests are not pedantry. A voice identifier comes out of a
// preference file this bridge did not write, and a repair tool that mis-parsed
// one would write the wrong identifier back into somebody's speech settings.

import Fakes
import Testing
import VoiceOverBridgeDomain

@testable import VoiceOverBridgeAdapters

@Suite("FileChangeJournal")
struct FileChangeJournalTests {
	private func journal() -> (FakeFileWriter, FileChangeJournal) {
		let writer = FakeFileWriter(path: "/logs/reader-changes.jsonl")
		return (writer, FileChangeJournal(writer: writer, timestamp: { "2026-09-02T14:11:03Z" }, pid: 4412))
	}

	private let voice = ReaderChange(
		kind: .voice, store: "com.apple.SpeakSelection / VoiceOverDefaultVoiceSelections / voiceId",
		was: "com.apple.voice.premium.pt-BR.Luciana", now: "the capture voice")

	@Test("a change is one flat JSON object, with the six fields in a fixed order")
	func aChangeIsOneLine() {
		let (writer, journal) = journal()
		journal.changed(voice)
		#expect(
			writer.lines == [
				"{\"at\":\"2026-09-02T14:11:03Z\",\"pid\":4412,\"change\":\"voice\",\"restored\":false,"
					+ "\"store\":\"com.apple.SpeakSelection / VoiceOverDefaultVoiceSelections / voiceId\","
					+ "\"was\":\"com.apple.voice.premium.pt-BR.Luciana\",\"now\":\"the capture voice\"}"
			])
	}

	@Test("a restore is the SAME line with `restored` true, so the two can be paired")
	func aRestoreIsPairable() {
		// What a repair tool does is match them up. A restore that described the
		// setting differently would leave an open change forever.
		let (writer, journal) = journal()
		journal.changed(voice)
		journal.restored(voice)
		#expect(writer.lines.count == 2)
		#expect(writer.lines[0].contains("\"restored\":false"))
		#expect(writer.lines[1].contains("\"restored\":true"))
		#expect(
			writer.lines[0].replacingOccurrences(of: "\"restored\":false", with: "")
				== writer.lines[1].replacingOccurrences(of: "\"restored\":true", with: ""))
	}

	@Test("`was` with nothing in it is null, never an empty string")
	func nothingIsNullAndNotEmpty() {
		// "There was no previous voice" and "the previous voice was the empty
		// string" are different, and a repair tool acting on the second would write
		// an empty identifier into somebody's speech preferences.
		let (writer, journal) = journal()
		journal.changed(ReaderChange(kind: .voice, store: "somewhere", was: nil, now: nil))
		#expect(writer.lines[0].contains("\"was\":null"))
		#expect(writer.lines[0].contains("\"now\":null"))
	}

	@Test("a value with quotes, backslashes or newlines cannot forge a line")
	func nothingCanForgeALine() {
		let (writer, journal) = journal()
		journal.changed(
			ReaderChange(
				kind: .voice, store: "s", was: "a\"b\\c\nd", now: "\u{01}"))
		#expect(writer.lines.count == 1)
		#expect(writer.lines[0].contains("\"was\":\"a\\\"b\\\\c\\nd\""))
		#expect(writer.lines[0].contains("\"now\":\"\\u0001\""))
	}

	@Test("nothing is written, and the file is not even opened, until something changes")
	func aQuietSessionLeavesNothing() {
		// Most of the value of this file is that a line in it MEANS something
		// happened, so a session that changed nothing must not touch it at all.
		let (writer, _) = journal()
		#expect(writer.lines.isEmpty)
		#expect(writer.openCount == 0)
	}

	@Test("the file is opened once, however many entries follow")
	func itOpensOnce() {
		let (writer, journal) = journal()
		journal.changed(voice)
		journal.restored(voice)
		#expect(writer.openCount == 1)
	}

	@Test("it lives beside the transcripts, under one fixed name")
	func itLivesBesideTheTranscripts() {
		// ONE FILE FOR THE WHOLE MACHINE: a repair needs every session's unfinished
		// business, and a crashed session cannot be relied on to name its own file.
		let path = FileChangeJournal.defaultPath(home: "/Users/someone")
		#expect(path == "/Users/someone/Library/Logs/screen-readers-mcp/reader-changes.jsonl")
		#expect(path.hasPrefix(FileTranscript.defaultLogDirectory(home: "/Users/someone")))
	}

	@Test("the running modifier is the one kind a tool must not try to WRITE back")
	func theRunningModifierIsNotRepairableByWriting() {
		// The preference FILE holds the person's own value the whole time (spec 0053
		// §3.3); what is ours is the running reader. A tool that "fixed" that by
		// writing the file would break the one thing §3.3 got right.
		#expect(!ReaderChange.Kind.runningModifier.repairableByWriting)
		#expect(ReaderChange.Kind.voice.repairableByWriting)
		#expect(ReaderChange.Kind.modifier.repairableByWriting)
	}
}
