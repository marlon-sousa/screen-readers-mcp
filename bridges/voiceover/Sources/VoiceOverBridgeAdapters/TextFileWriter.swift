// ROLE: LEAF adapter -- IMPLEMENTS the FileWriter seam by doing the real file IO.
//
// USED BY: FileTranscript, through the seam, never directly.
// BUILT BY: Wiring / FileTranscript's own composition helper.
//
// DELIBERATELY THE DUMBEST FILE IN THE BRIDGE. It makes no decisions, so there
// is nothing a unit test could assert here that the filesystem does not already
// guarantee -- which is why it has no test file. Everything worth testing lives
// one layer up in FileTranscript, exercised against a fake writer. Keep it that
// way: a decision that turns up here belongs upstairs.
//
// THE HANDLE IS DELIBERATELY LONG-LIVED. It stays open for the whole session and
// is closed by `close()`, so there is no scope-based form of this that would not
// shut the file before the first line was written.

import Foundation

public final class TextFileWriter: FileWriter {
	public let path: String
	private var handle: FileHandle?

	public init(path: String) {
		self.path = path
	}

	public func open() throws {
		let url = URL(fileURLWithPath: path)
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		FileManager.default.createFile(atPath: path, contents: nil)
		handle = try FileHandle(forWritingTo: url)
	}

	public func writeLine(_ text: String) {
		guard let handle, let data = (text + "\n").data(using: .utf8) else { return }
		// Written and flushed per line, and every failure swallowed: a transcript
		// that cannot be written must never take a session down, nor stop the
		// teardown that gives a human their screen reader back.
		do {
			try handle.write(contentsOf: data)
			try handle.synchronize()
		} catch {
		}
	}

	public func close() {
		try? handle?.close()
		handle = nil
	}
}
