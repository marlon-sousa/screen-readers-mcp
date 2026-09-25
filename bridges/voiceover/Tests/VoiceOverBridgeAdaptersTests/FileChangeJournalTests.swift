// Mirrors Sources/VoiceOverBridgeAdapters/FileChangeJournal.swift.

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
		let path = FileChangeJournal.defaultPath(home: "/Users/someone")
		#expect(path == "/Users/someone/Library/Logs/screen-readers-mcp/reader-changes.jsonl")
		#expect(path.hasPrefix(FileTranscript.defaultLogDirectory(home: "/Users/someone")))
	}

	@Test("the kinds are exactly what this build can emit")
	func theKindsAreWhatCanBeEmitted() {
		#expect(ReaderChange.Kind.allCases == [.voice])
	}
}
