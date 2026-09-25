// Hand-written stateful fake for the ReaderRestart port.

import VoiceOverBridgeDomain

public final class FakeReaderRestart: ReaderRestart {
	public private(set) var restarts = 0

	public var failure: ReaderRestartError?

	public var onRestart: (() -> Void)?

	public init() {}

	public func restart() throws {
		if let failure { throw failure }
		restarts += 1
		onRestart?()
	}
}
