// Hand-written stateful fake for the LineTailer adapter seam; lines are delivered on the caller's thread.

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

	public func deliver(_ line: String) {
		onLine?(line)
	}
}
