// ROLE: adapter seam -- is an application running on this machine right now?
//
// NOT A DOMAIN PORT: the domain asks whether the READER is there
// (`ReaderLiveness`) and has no idea that the answer is a bundle identifier in a
// list the window server keeps. This is the seam between two adapters, which is
// the only way one adapter may depend on another (AGENTS.md).
//
// IMPLEMENTED BY: WorkspaceRunningApplications (the leaf, `NSWorkspace`) and
// FakeRunningApplications (Tests/Fakes).
// USED BY: VoiceOverLiveness, and nothing else.
//
// ============================================================================
// IT EXISTS BECAUSE THE OLD ANSWER COST A PERMISSION IT DID NOT NEED -- 13.26.
// ============================================================================
//
// Until this entry "is VoiceOver running" was answered by sending it an
// AppleEvent -- `tell application "VoiceOver" to return name`. That works, and it
// was chosen for a good reason (spec 0041: an application-level property answers
// when the scripting object model is dead, which is what separates two failures
// that otherwise look identical). But it means the handshake could not confirm
// the reader existed without the Automation grant, on a machine that may have
// been intending to drive the reader entirely by keystrokes.
//
// And the requirement behind 13.26 is sharper than convenience. "Allow VoiceOver
// to be controlled with AppleScript" lets ANY process drive the screen reader a
// blind person depends on; a bridge that makes them leave it on to be tested is
// asking them to hold a door open for everyone. So every use of that channel had
// to be justified, and this one could not be: the running-application list is
// public, costs NO permission, cannot be switched off, and answers the question
// more exactly than the AppleEvent did.
//
// WHAT IT DELIBERATELY DOES NOT ANSWER is whether the reader is HEALTHY. A
// process can be running and its scripting object model dead (measured, spec
// 0041), and it can be running and not seeing synthesized key events (measured,
// 13.22's live run). Those are separate conditions with separate recoveries, and
// the caller names them -- see `PressGestureHandler.explain`, which combines this
// answer with the AppleScript switch's state to say which of three things is
// true. A seam that tried to answer "is it well" would be a second copy of the
// failing call rather than a control for it.

public protocol RunningApplications: AnyObject {
	/// Whether any running application has this bundle identifier.
	func isRunning(bundleIdentifier: String) -> Bool
}
