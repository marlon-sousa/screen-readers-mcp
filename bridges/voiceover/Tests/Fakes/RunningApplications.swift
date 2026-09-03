// A hand-written stateful fake for the RunningApplications adapter seam,
// mirroring Sources/VoiceOverBridgeAdapters/Ports/RunningApplications.swift.
//
// IT RECORDS WHAT IT WAS ASKED ABOUT, which is most of the point: the adapter
// above it is only correct if it asks about VoiceOver's own bundle identifier,
// and a fake that answered without saying what it was asked could not check that.

import VoiceOverBridgeAdapters

public final class FakeRunningApplications: RunningApplications {
	public var running: Set<String>
	public private(set) var asked: [String] = []

	/// Called before each answer, so a test can make the machine CHANGE while
	/// something is polling it.
	///
	/// IT ARRIVED WITH 13.26's RESTART, whose whole point is a WAIT: `killall`
	/// returns when the signal is sent, not when the process is gone, so the class
	/// polls -- and a fake that could only answer one thing forever could not tell
	/// a restart that waits from one that got lucky. Same shape and same reason as
	/// `FakeProcessRunner.beforeRun`.
	public var beforeAsk: (() -> Void)?

	/// Defaults to a machine where VoiceOver IS running, which is the ordinary
	/// case and keeps a test that does not care about liveness readable.
	public init(running: Set<String> = ["com.apple.VoiceOver"]) {
		self.running = running
	}

	public func isRunning(bundleIdentifier: String) -> Bool {
		beforeAsk?()
		asked.append(bundleIdentifier)
		return running.contains(bundleIdentifier)
	}
}
