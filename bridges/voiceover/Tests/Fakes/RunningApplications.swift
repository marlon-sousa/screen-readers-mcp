// Hand-written stateful fake for the RunningApplications adapter seam.

import VoiceOverBridgeAdapters

public final class FakeRunningApplications: RunningApplications {
	public var running: Set<String>
	public private(set) var asked: [String] = []

	public var beforeAsk: (() -> Void)?

	public init(running: Set<String> = ["com.apple.VoiceOver"]) {
		self.running = running
	}

	public func isRunning(bundleIdentifier: String) -> Bool {
		beforeAsk?()
		asked.append(bundleIdentifier)
		return running.contains(bundleIdentifier)
	}
}
