// A hand-written stateful fake for the LineTailer adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/LineTailer.swift.
//
// A test hands it lines and they are delivered on the caller's thread, so
// ContainerFileSpeechSource's decisions -- which lines are utterances, what the
// words are, whose numbering wins -- are asserted with no file, no thread and no
// waiting. What the fake CANNOT prove is that a real file behaves like this;
// that is FileLineTailerTests' job, and it uses a real file for exactly that
// reason.

import VoiceOverBridgeAdapters

public final class FakeLineTailer: LineTailer {
	private var onLine: ((String) -> Void)?
	public private(set) var startCount = 0
	public private(set) var stopCount = 0

	public var isTailing: Bool { onLine != nil }

	public init() {}

	public func start(_ onLine: @escaping (String) -> Void) {
		startCount += 1
		self.onLine = onLine
	}

	public func stop() {
		stopCount += 1
		onLine = nil
	}

	/// Deliver one line, as a real tailer would once its newline arrived. Lines
	/// sent while stopped go nowhere, which is what a stopped tailer does.
	public func deliver(_ line: String) {
		onLine?(line)
	}
}
