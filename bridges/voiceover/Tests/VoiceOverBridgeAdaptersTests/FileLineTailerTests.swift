// Mirrors Sources/VoiceOverBridgeAdapters/FileLineTailer.swift.
//
// IT DRIVES A REAL FILE, and that is the amendment this entry makes to spec
// 0046's layout, argued in the class's own header: everything this adapter
// decides is about what a real file does -- appearing after capture started,
// growing between two reads, splitting a line across them -- and a fake seam
// would only prove those behave as the fake was written to behave. This lane
// drives real sockets for the same reason.
//
// EVERY TEST HAS A DEADLINE AND POLLS. The tailer runs on a thread of its own,
// so an assertion made immediately would be asserting on scheduling. The poll
// interval is turned right down, so these finish in milliseconds.

import Foundation
import Testing

@testable import VoiceOverBridgeAdapters

@Suite("FileLineTailer")
struct FileLineTailerTests {
	/// A fresh directory per test, removed afterwards, so no two tests and no
	/// developer's own capture file can see each other.
	private final class Scratch {
		let directory: URL
		let path: String

		init() {
			directory = URL(fileURLWithPath: NSTemporaryDirectory())
				.appendingPathComponent("tailer-\(UUID().uuidString)")
			try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			path = directory.appendingPathComponent("feed.jsonl").path
		}

		func write(_ text: String) {
			if let handle = FileHandle(forWritingAtPath: path) {
				defer { try? handle.close() }
				try? handle.seekToEnd()
				try? handle.write(contentsOf: Data(text.utf8))
			} else {
				try? Data(text.utf8).write(to: URL(fileURLWithPath: path))
			}
		}

		func remove() {
			try? FileManager.default.removeItem(at: directory)
		}
	}

	/// Lines delivered so far, guarded because the tailer's thread appends to it.
	private final class Sink {
		private let lock = NSLock()
		private var lines: [String] = []

		var collected: [String] {
			lock.lock()
			defer { lock.unlock() }
			return lines
		}

		func append(_ line: String) {
			lock.lock()
			lines.append(line)
			lock.unlock()
		}
	}

	private func waitUntil(_ condition: () -> Bool, seconds: Double = 5) -> Bool {
		let deadline = Date().addingTimeInterval(seconds)
		while Date() < deadline {
			if condition() { return true }
			usleep(2000)
		}
		return condition()
	}

	private func tailer(_ scratch: Scratch) -> FileLineTailer {
		FileLineTailer(path: scratch.path, pollInterval: 0.005)
	}

	@Test("a file that already exists is followed from its END, not from the top")
	func historyIsNotReplayed() {
		// The capture voice appends to one file across every launch of the
		// reader. A tailer that started at byte zero would pour days of old
		// speech into a fresh session's buffer as though it had just been said.
		let scratch = Scratch()
		defer { scratch.remove() }
		scratch.write("old line one\nold line two\n")

		let sink = Sink()
		let tail = tailer(scratch)
		tail.start { sink.append($0) }
		defer { tail.stop() }

		scratch.write("new line\n")
		#expect(waitUntil { sink.collected == ["new line"] })
	}

	@Test("a file that does not exist yet is waited for, and then read whole")
	func aFileThatArrivesLate() {
		// The extension creates it the first time the reader speaks through our
		// voice, which is routinely after the session began -- so "not there" is
		// a state to poll through, and everything written to it is new.
		let scratch = Scratch()
		defer { scratch.remove() }

		let sink = Sink()
		let tail = tailer(scratch)
		tail.start { sink.append($0) }
		defer { tail.stop() }

		#expect(waitUntil({ sink.collected.isEmpty }, seconds: 0.1))
		scratch.write("first ever line\n")
		#expect(waitUntil { sink.collected == ["first ever line"] })
	}

	@Test("a line split across two writes is delivered ONCE, whole")
	func partialLinesAreHeld() {
		// A read can land mid-line. Delivered early, the JSON would not parse and
		// the utterance would be lost; delivered twice, it would be captured
		// twice.
		let scratch = Scratch()
		defer { scratch.remove() }
		scratch.write("")

		let sink = Sink()
		let tail = tailer(scratch)
		tail.start { sink.append($0) }
		defer { tail.stop() }

		scratch.write("{\"event\":\"synth")
		#expect(waitUntil({ !sink.collected.isEmpty }, seconds: 0.15) == false)
		scratch.write("esize\"}\n")
		#expect(waitUntil { sink.collected == ["{\"event\":\"synthesize\"}"] })
	}

	@Test("several lines in one write arrive separately and in order")
	func manyLinesInOneWrite() {
		let scratch = Scratch()
		defer { scratch.remove() }
		scratch.write("")

		let sink = Sink()
		let tail = tailer(scratch)
		tail.start { sink.append($0) }
		defer { tail.stop() }

		scratch.write("one\ntwo\nthree\n")
		#expect(waitUntil { sink.collected == ["one", "two", "three"] })
	}

	@Test("a trailing line with no newline is held until it has one")
	func theTailIsNotGuessedAt() {
		let scratch = Scratch()
		defer { scratch.remove() }
		scratch.write("")

		let sink = Sink()
		let tail = tailer(scratch)
		tail.start { sink.append($0) }
		defer { tail.stop() }

		scratch.write("complete\nincomplete")
		#expect(waitUntil { sink.collected == ["complete"] })
		#expect(waitUntil({ sink.collected.count > 1 }, seconds: 0.1) == false)
	}

	@Test("nothing is delivered after stop, and stopping twice is safe")
	func stopping() {
		let scratch = Scratch()
		defer { scratch.remove() }
		scratch.write("")

		let sink = Sink()
		let tail = tailer(scratch)
		tail.start { sink.append($0) }
		scratch.write("before the stop\n")
		#expect(waitUntil { sink.collected == ["before the stop"] })

		tail.stop()
		tail.stop()
		scratch.write("after the stop\n")
		#expect(waitUntil({ sink.collected.count > 1 }, seconds: 0.2) == false)
	}

	@Test("starting twice does not start a second thread, so nothing is delivered twice")
	func startingTwice() {
		let scratch = Scratch()
		defer { scratch.remove() }
		scratch.write("")

		let sink = Sink()
		let tail = tailer(scratch)
		tail.start { sink.append($0) }
		tail.start { sink.append($0) }
		defer { tail.stop() }

		scratch.write("once\n")
		#expect(waitUntil { sink.collected == ["once"] })
		#expect(waitUntil({ sink.collected.count > 1 }, seconds: 0.2) == false)
	}
}
