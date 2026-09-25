// Hand-written stateful fake for the ReaderLiveness port.

import VoiceOverBridgeDomain

public final class FakeReaderLiveness: ReaderLiveness {
	public var isRunning: Bool
	public private(set) var asked = 0
	public private(set) var activations = 0

	public var activationSucceeds = true

	public init(isRunning: Bool = true) {
		self.isRunning = isRunning
	}

	public func readerIsRunning() -> Bool {
		asked += 1
		return isRunning
	}

	public func activate() {
		activations += 1
		if activationSucceeds { isRunning = true }
	}
}
