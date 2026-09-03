// ROLE: LEAF adapter -- IMPLEMENTS the FileWriter seam over a file that is
// APPENDED to rather than replaced. Real file IO, no decisions.
//
// USED BY: FileChangeJournal, through the seam, never directly.
// BUILT BY: Wiring.
//
// NO TEST FILE (leaf), like `TextFileWriter` beside it: everything worth
// asserting is the journal's line format, one layer up, against a fake writer.
//
// ============================================================================
// IT IS A SECOND LEAF RATHER THAN A FLAG ON THE FIRST, AND THE REASON IS A BUG
// THAT WOULD HAVE BEEN INVISIBLE.
// ============================================================================
//
// `TextFileWriter.open()` calls `FileManager.createFile(atPath:contents:)`, which
// TRUNCATES an existing file. That is exactly right for a transcript: every
// session gets a fresh `session-<stamp>.log`, so there is never anything to
// truncate, and starting from empty is what you want if there somehow were.
//
// The change journal is the opposite in every respect. It is ONE file for the
// whole machine, appended to by every session, and its entire value is that an
// entry written three weeks ago is still there when somebody finally notices
// their voice is wrong. Reusing the transcript's leaf would have wiped every
// unresolved change on the next connect -- and it would have looked like it was
// working, because the session that wiped the file immediately writes its own
// entries into it. The evidence destroyed is always somebody ELSE's.
//
// So the two behaviours get two classes, and a caller picks by NAME rather than
// by remembering a boolean. That is the same rule this bridge applies to
// `PlistReader` and `PlistWriter`: the object you were handed decides what you
// can do to somebody's machine.
//
// IT CREATES THE FILE WHEN THERE IS NONE, and seeks to the end when there is.
// Both are what "append" means to whoever asked for it.

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
		// Written and flushed per line, and every failure swallowed -- the seam's
		// contract. The tail is exactly what a crash would take, and a crash is the
		// only reason this file exists.
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
