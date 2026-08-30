// A hand-written stateful fake for the FileWriter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/FileWriter.swift.
//
// It records lines in memory, which is what lets FileTranscript's test assert
// the exact text of a transcript with no filesystem -- and therefore assert on
// the FORMAT, which is the only thing that adapter decides.

import VoiceOverBridgeAdapters

public final class FakeFileWriter: FileWriter {
	public let path: String
	public private(set) var lines: [String] = []
	public private(set) var openCount = 0
	public private(set) var closeCount = 0

	public init(path: String = "/tmp/fake-transcript.log") {
		self.path = path
	}

	public func open() throws {
		openCount += 1
	}

	public func writeLine(_ text: String) {
		lines.append(text)
	}

	public func close() {
		closeCount += 1
	}
}
