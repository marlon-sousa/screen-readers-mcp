// ROLE: leaf adapter implementing the FileWriter seam with real file IO.
// USED BY: FileTranscript, through the seam.
// BUILT BY: `FileTranscript.session(in:)`.

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
		// Every failure is swallowed: a transcript that cannot be written must never end a session or stop the teardown that restores the reader.
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
