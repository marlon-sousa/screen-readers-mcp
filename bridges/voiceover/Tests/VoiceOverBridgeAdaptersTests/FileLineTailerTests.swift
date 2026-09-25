// Mirrors Sources/VoiceOverBridgeAdapters/FileLineTailer.swift.

import Foundation
import Testing

@testable import VoiceOverBridgeAdapters

@Suite("FileLineTailer")
struct FileLineTailerTests {
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
