// ROLE: LEAF adapter -- IMPLEMENTS the RunningApplications seam over
// `NSRunningApplication`. Real system state, no decisions.
//
// BUILT BY: Wiring. USED BY: VoiceOverLiveness, through the seam.
//
// NO TEST FILE (leaf): there is nothing here that
// `NSRunningApplication.runningApplications(withBundleIdentifier:)` does not
// already guarantee, and a test could only assert against whatever the developer
// happens to have open. If you are adding a test here, a decision has landed in a
// leaf and belongs one layer up.
//
// THE IDENTIFIER IS CASE-SENSITIVE, AND A WRONG ONE ANSWERS "NOT RUNNING"
// FOREVER. Measured 2026-09-02: `com.apple.VoiceOver` finds the reader and
// `com.apple.voiceover` returns an empty list with no error at all. So the one
// spelling that matters is a constant on `VoiceOverLiveness`, read out of
// `/System/Library/CoreServices/VoiceOver.app/Contents/Info.plist` rather than
// recalled, and a test asserts the adapter asks for exactly it -- because the
// failure mode here is a handshake that reports a dead reader on a healthy
// machine, which is the shape this lane keeps paying for.
//
// IT COSTS NO PERMISSION, WHICH IS THE WHOLE REASON 13.26 REACHED FOR IT. The
// running-application list is public: no Accessibility, no Automation, no
// AppleScript switch, and nothing a human can turn off. The question "is the
// reader there" had been costing an AppleEvent, and with it a grant the session
// might have had no other use for.

import AppKit

public final class WorkspaceRunningApplications: RunningApplications {
	public init() {}

	public func isRunning(bundleIdentifier: String) -> Bool {
		!NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
	}
}
