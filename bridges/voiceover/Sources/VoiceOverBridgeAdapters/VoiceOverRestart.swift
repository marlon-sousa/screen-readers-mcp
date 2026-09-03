// ROLE: adapter -- IMPLEMENTS the ReaderRestart domain port. It holds the ONE
// sequence that actually restarts this reader, and the waits that make it a
// sequence rather than a race.
//
// BUILT BY: VoiceOverAdapterFactory. USED BY: ReaderEdgeSetup's modifier rung and
// Session.teardown, through the port. HOLDS: a ProcessRunner (to run the two
// tools), the RunningApplications seam (to see the process go and come back) and
// a Clock (to wait) -- which is `PluginKitProviderLifecycle`'s existing shape,
// for the same reason: a poll with an injected clock costs microseconds in a test
// and real seconds on a real machine.
//
// ============================================================================
// `killall VoiceOver && open -a VoiceOver` IS WRONG, AND THIS REPOSITORY PRINTED
// IT AS ADVICE FOR WEEKS.
// ============================================================================
//
// Two independent defects, both paid for on the maintainer's machine:
//
//   * `killall` ALONE does not relaunch the reader -- measured 2026-08-31. A
//     human who ran only the first half of that line was left with no screen
//     reader at all, which is why every sentence in this repo spells the restart
//     as a pair.
//   * THE `&&` RACES. `killall` returns when the SIGNAL IS SENT, not when the
//     process is gone. `open -a` on an application the system still believes is
//     running does nothing, so the pair can leave the reader stopped, or restart
//     it into a state where its scripting object model never comes up. The
//     2026-09-02 field report is very probably that: following this repository's
//     own instruction left every scripting call answering `-1728`, and it cost
//     about twenty minutes and an interruption of the blind user at the machine
//     before Command-F5 fixed what `open -a` had not.
//
// SO THE WAIT IS THE FIX, and it is between the two halves rather than after
// them: quit, POLL UNTIL THE PROCESS IS ACTUALLY GONE, then start, then poll
// until it is back. Both waits are bounded and both name themselves on failure.
//
// ============================================================================
// IT REPORTS WHICH HALF FAILED, BECAUSE THE TWO OUTCOMES ARE OPPOSITE.
// ============================================================================
//
// "I could not stop VoiceOver" leaves somebody with a working screen reader and
// a session that will not start. "I stopped VoiceOver and it did not come back"
// leaves a blind person sitting in silence in front of a machine they cannot
// drive. `ReaderRestartError.readerStillRunning` carries that difference so a
// caller can say the right one, and this class never collapses them.
//
// IT MAKES NO SOUND. Spec 0053 §3.2 requires a restart to be ANNOUNCED first,
// through the bridge's own synthesizer, because it is audible even when the
// reader is silenced. That is the controller's obligation: only the controller
// knows WHY it is restarting, and only the controller holds the announcer.

import VoiceOverBridgeDomain

public final class VoiceOverRestart: ReaderRestart {
	/// How the reader is stopped. `killall` by name, which is what was measured;
	/// nothing here sends an AppleEvent, because the whole point of 13.26 is a
	/// machine where that channel may be switched off.
	public static let killTool = "/usr/bin/killall"

	/// How the reader is started. The same tool `VoiceOverLiveness.activate` uses,
	/// deliberately: one way to start this reader, not two that agree today.
	public static let openTool = VoiceOverLiveness.openTool

	/// How long the reader is given to go away, and to come back.
	///
	/// GENEROUS, AND ASYMMETRIC ONLY IN CONSEQUENCE. VoiceOver saves state on the
	/// way down and rebuilds an accessibility world on the way up, and a wait that
	/// was too tight would report a healthy machine as broken -- which, on the way
	/// UP, means abandoning a restart half done.
	public static let quitSeconds: Double = 10.0
	public static let startSeconds: Double = 20.0

	/// How often the two waits re-ask. Injected clock, so a test pays none of it.
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

	/// Stop the reader, and do not return until it is gone.
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

	/// Start the reader, and do not return until it is back.
	///
	/// EVERY FAILURE FROM HERE ON REPORTS `readerStillRunning: false`, and it is
	/// the most important thing this class says: there is a person who may be
	/// sitting in silence, and whoever reads this has to tell them so.
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

	/// Poll `condition` until it holds, or until `seconds` have passed. Checked
	/// immediately first, so a condition that is already true costs nothing.
	private func waitUntil(seconds: Double, _ condition: () -> Bool) -> Bool {
		let deadline = clock.monotonic() + seconds
		while true {
			if condition() { return true }
			guard clock.monotonic() < deadline else { return false }
			clock.sleep(Self.pollInterval)
		}
	}
}
