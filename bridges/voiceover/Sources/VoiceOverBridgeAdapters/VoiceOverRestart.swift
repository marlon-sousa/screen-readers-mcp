// ROLE: adapter implementing the ReaderRestart port: the one sequence that restarts this reader, and the waits that keep it from racing.
// BUILT BY: Wiring, once per process.
// USED BY: ReaderEdgeSetup, through the port.
// `killall VoiceOver && open -a VoiceOver` races: `killall` returns once the signal is sent and `open -a` does nothing to an application still running, so quit waits until the process is gone.
// `readerStillRunning` tells a failed stop, which leaves a working reader, from a failed start, which leaves a blind user in silence.
// Makes no sound: announcing the restart first is the caller's obligation.

import VoiceOverBridgeDomain

public final class VoiceOverRestart: ReaderRestart {
	/// `killall` by name; nothing here sends an AppleEvent.
	public static let killTool = "/usr/bin/killall"

	/// The same tool `VoiceOverLiveness.activate` uses, so there is one way to start this reader.
	public static let openTool = VoiceOverLiveness.openTool

	/// Generous: too tight a wait reports a healthy machine as broken, and on the way up abandons a restart half done.
	public static let quitSeconds: Double = 10.0
	public static let startSeconds: Double = 20.0

	static let pollInterval: Double = 0.25

	private let tools: any ProcessRunner
	private let applications: any RunningApplications
	private let clock: any Clock

	public init(tools: any ProcessRunner, applications: any RunningApplications, clock: any Clock) {
		self.tools = tools
		self.applications = applications
		self.clock = clock
	}

	public func restart() throws {
		try quit()
		try start()
	}

	private func quit() throws {
		guard running else { return }
		do {
			_ = try tools.run(Self.killTool, ["VoiceOver"])
		} catch {
			throw ReaderRestartError(
				"VoiceOver could not be stopped -- \(Self.killTool) would not run: \(error)",
				readerStillRunning: running)
		}
		guard waitUntil(seconds: Self.quitSeconds, { !self.running }) else {
			throw ReaderRestartError(
				"VoiceOver was asked to stop and was still running \(Int(Self.quitSeconds)) seconds "
					+ "later. Nothing was restarted, so the reader is exactly as it was.",
				readerStillRunning: true)
		}
	}

	/// Every failure from here reports `readerStillRunning: false`: somebody may be sitting in silence.
	private func start() throws {
		do {
			_ = try tools.run(Self.openTool, ["-a", "VoiceOver"])
		} catch {
			throw ReaderRestartError(
				"VoiceOver was stopped and could not be started again -- \(Self.openTool) would not "
					+ "run: \(error). THE READER IS NOT RUNNING.",
				readerStillRunning: false)
		}
		guard waitUntil(seconds: Self.startSeconds, { self.running }) else {
			throw ReaderRestartError(
				"VoiceOver was stopped and had not come back \(Int(Self.startSeconds)) seconds after "
					+ "being started. THE READER IS NOT RUNNING: the person at this machine has no "
					+ "screen reader until it is started, and Command-F5 is what they press.",
				readerStillRunning: false)
		}
	}

	private var running: Bool {
		applications.isRunning(bundleIdentifier: VoiceOverLiveness.readerBundleIdentifier)
	}

	private func waitUntil(seconds: Double, _ condition: () -> Bool) -> Bool {
		let deadline = clock.monotonic() + seconds
		while true {
			if condition() { return true }
			guard clock.monotonic() < deadline else { return false }
			clock.sleep(Self.pollInterval)
		}
	}
}
