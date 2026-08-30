// Mirrors Sources/VoiceOverBridgeAdapters/FileTranscript.swift.
//
// It asserts the exact lines, because the format is the only thing this adapter
// decides -- and because the file is the only record a silent run leaves, so a
// changed shape is a changed record with nothing to compare it against.

import Fakes
import Testing

@testable import VoiceOverBridgeAdapters

@Suite("FileTranscript")
struct FileTranscriptTests {
	private func transcript(_ writer: FakeFileWriter) -> FileTranscript {
		FileTranscript(writer: writer, timestamp: { "2026-08-30 10:00:00.000" })
	}

	@Test("a session's open and close lines carry the mode, the voice and the reason")
	func theSessionLines() {
		let writer = FakeFileWriter()
		let record = transcript(writer)
		record.open()
		record.sessionOpened(mode: "live", voice: "capture voice", persona: "tester")
		record.sessionClosed(reason: "client-bye")
		#expect(
			writer.lines == [
				"2026-08-30 10:00:00.000 SESSION OPEN mode=live voice=capture voice persona=tester",
				"2026-08-30 10:00:00.000 SESSION CLOSE reason=client-bye",
			]
		)
	}

	@Test("a dispatched command is one QUOTED line, for the reason speech is")
	func gesturesAreQuoted() {
		// Same quoting as speech and for the same reason: a gesture id is opaque
		// text off the wire, and the record is a line-oriented file somebody reads
		// afterwards to work out what a run did to their machine.
		let writer = FakeFileWriter()
		let record = transcript(writer)
		record.open()
		record.gesture("go to desktop")
		#expect(writer.lines == ["2026-08-30 10:00:00.000 GESTURE \"go to desktop\""])
	}

	@Test("no persona is written as a dash, so every open line has the same shape")
	func anAbsentPersonaKeepsTheShape() {
		let writer = FakeFileWriter()
		let record = transcript(writer)
		record.open()
		record.sessionOpened(mode: "live", voice: "v", persona: "")
		#expect(writer.lines[0].hasSuffix("persona=-"))
	}

	@Test("a captured utterance is one QUOTED line, so the words cannot forge another")
	func speechIsQuoted() {
		let writer = FakeFileWriter()
		let record = transcript(writer)
		record.open()
		record.speech("Documents, folder")
		record.speech("a line\nand another")
		#expect(
			writer.lines == [
				"2026-08-30 10:00:00.000 SPEECH \"Documents, folder\"",
				// The newline is escaped rather than written: the words come from
				// another process, and one utterance must stay one line.
				"2026-08-30 10:00:00.000 SPEECH \"a line\\nand another\"",
			]
		)
	}

	@Test("a quote inside an utterance is escaped, not left to close the record early")
	func quotesAreEscaped() {
		let writer = FakeFileWriter()
		let record = transcript(writer)
		record.open()
		record.speech("she said \"hello\"")
		#expect(writer.lines[0].hasSuffix("SPEECH \"she said \\\"hello\\\"\""))
	}

	@Test("speech outside an open session is dropped, like every other event")
	func speechBeforeOpen() {
		// There is no session for a reader of the file to attach it to, so it is
		// dropped rather than buffered -- the same rule the other verbs follow.
		let writer = FakeFileWriter()
		transcript(writer).speech("said")
		#expect(writer.lines.isEmpty)
	}

	@Test("a note is one line, timestamped like the rest")
	func notes() {
		let writer = FakeFileWriter()
		let record = transcript(writer)
		record.open()
		record.note("unreadable message: line is not JSON")
		#expect(writer.lines == ["2026-08-30 10:00:00.000 NOTE unreadable message: line is not JSON"])
	}

	@Test("events outside an open session are DROPPED, not buffered")
	func nothingIsWrittenBeforeOpen() {
		let writer = FakeFileWriter()
		let record = transcript(writer)
		// There is no session for a reader of the file to attach them to, and a
		// line whose session is a guess is worse than no line.
		record.note("before")
		record.open()
		record.note("during")
		record.sessionClosed(reason: "client-bye")
		record.note("after")
		#expect(writer.lines.count == 2)
		#expect(writer.lines[0].hasSuffix("NOTE during"))
	}

	@Test("closing the session closes the file under it")
	func closingClosesTheWriter() {
		let writer = FakeFileWriter()
		let record = transcript(writer)
		record.open()
		record.sessionClosed(reason: "external")
		#expect(writer.openCount == 1)
		#expect(writer.closeCount == 1)
	}

	@Test("the path it reports is the writer's -- what hello hands the agent")
	func thePathIsTheWriters() {
		#expect(transcript(FakeFileWriter(path: "/logs/s.log")).logPath == "/logs/s.log")
	}
}
