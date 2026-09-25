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
