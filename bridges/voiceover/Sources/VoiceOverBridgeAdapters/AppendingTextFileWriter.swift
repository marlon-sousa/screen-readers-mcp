// ROLE: leaf adapter that implements the FileWriter seam over a file appended to, never replaced.
// USED BY: FileChangeJournal, through the seam.
// BUILT BY: Wiring.
// Never swap in TextFileWriter here: its `open()` truncates, which would wipe every earlier session's
// unresolved changes from the journal.

import Foundation

public final class AppendingTextFileWriter: FileWriter {
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
		if !FileManager.default.fileExists(atPath: path) {
			FileManager.default.createFile(atPath: path, contents: nil)
		}
		let opened = try FileHandle(forWritingTo: url)
		try opened.seekToEnd()
		handle = opened
	}

	public func writeLine(_ text: String) {
		guard let handle, let data = (text + "\n").data(using: .utf8) else { return }
		// Written and flushed per line, and every failure swallowed, per the seam's contract.
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
