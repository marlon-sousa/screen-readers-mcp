// ROLE: adapter seam asking whether an application is running on this machine now.
// IMPLEMENTED BY: WorkspaceRunningApplications and FakeRunningApplications.
// USED BY: VoiceOverLiveness.
// Answers only whether the process runs, not whether the reader is healthy; see `PressGestureHandler.explain`.

public protocol RunningApplications: AnyObject {
	func isRunning(bundleIdentifier: String) -> Bool
}
