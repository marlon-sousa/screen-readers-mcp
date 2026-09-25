// ROLE: leaf adapter implementing the RunningApplications seam over NSRunningApplication.
// BUILT BY: Wiring.
// USED BY: VoiceOverLiveness, through the seam.
// The bundle identifier matches case-sensitively: `com.apple.voiceover` returns an empty list and no error.
// It needs no permission: the running-application list is public.

import AppKit

public final class WorkspaceRunningApplications: RunningApplications {
	public init() {}

	public func isRunning(bundleIdentifier: String) -> Bool {
		!NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
	}
}
