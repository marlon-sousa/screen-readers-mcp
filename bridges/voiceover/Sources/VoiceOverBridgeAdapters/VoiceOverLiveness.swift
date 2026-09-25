// ROLE: adapter implementing the ReaderLiveness port over the RunningApplications seam.
// BUILT BY: VoiceOverAdapterFactory.
// USED BY: the PressGesture handler, after a dispatch failed, and ReaderEdgeSetup, before anything is asked of the reader.
// Measured with VoiceOver on macOS 15: `killall VoiceOver` does not relaunch the reader, and `open -a VoiceOver` does.
// Swallows every error: each way this can fail is a "no" to its caller.

import VoiceOverBridgeDomain

public final class VoiceOverLiveness: ReaderLiveness {
	public static let readerBundleIdentifier = "com.apple.VoiceOver"

	/// `open` starts the reader; nothing here ever kills it.
	public static let openTool = "/usr/bin/open"

	private let applications: any RunningApplications
	private let tools: any ProcessRunner

	public init(applications: any RunningApplications, tools: any ProcessRunner) {
		self.applications = applications
		self.tools = tools
	}

	public func readerIsRunning() -> Bool {
		applications.isRunning(bundleIdentifier: Self.readerBundleIdentifier)
	}

	/// Returns at once without reporting; `readerIsRunning` afterwards is the only evidence.
	public func activate() {
		_ = try? tools.run(Self.openTool, ["-a", "VoiceOver"])
	}
}
