// ROLE: adapter -- IMPLEMENTS the ReaderLiveness domain port, over the
// RunningApplications seam.
//
// BUILT BY: VoiceOverAdapterFactory. USED BY: the PressGesture handler, through
// the port, and only after a dispatch has already failed; and by
// ReaderEdgeSetup's rung 2, before anything is asked of the reader.
//
// ============================================================================
// IT USED TO ASK BY APPLEEVENT, AND 13.26 STOPPED IT. THAT IS THE ENTRY TO READ.
// ============================================================================
//
// The old probe was `tell application "VoiceOver" to return name` -- an
// APPLICATION-level property, chosen because it answers when the scripting object
// model is dead, which is what separates two failures that otherwise look
// identical (spec 0041 measured exactly that state). It worked. What it cost was
// a PERMISSION: the handshake could not confirm the reader existed without the
// Automation grant, on a machine that may have intended to drive the reader
// entirely by keystrokes and needed no AppleEvents at all.
//
// THE SCRIPT ITSELF OUTLIVED THE PROBE BY FIVE ENTRIES AND IS NOW GONE TOO. It
// stayed public because `TCCPermissionBroker` sent it to read the Automation
// grant -- the only way to learn a permission that belonged to the CHANNEL rather
// than to this binary. 13.31 deleted the command-name route, so there is no
// channel, no grant to read and no script anywhere in this bridge (spec 0055).
//
// And the requirement behind 13.26 is sharper than convenience: "Allow VoiceOver
// to be controlled with AppleScript" lets ANY process drive the screen reader a
// blind person depends on, so every use of that channel had to justify itself.
// This one could not. The running-application list answers the same question with
// NO permission, cannot be switched off, and is exact where the AppleEvent was a
// proxy.
//
// THE DISTINCTION SPEC 0041 NEEDED IS NOT LOST; IT STOPPED EXISTING. That spec
// required "the process is there but its object model is not" be reported as a
// named condition, and 13.26 composed it from this answer plus the AppleScript
// switch. There is no object model in this bridge since 13.31, so what is left for
// a caller to ask is the plain question this class was always best at: is the
// reader there at all. See `PressGestureHandler.explain`.
//
// AND SINCE 13.20 IT CAN START THE READER, WHICH IS THE OPPOSITE QUESTION ASKED
// BY A DIFFERENT CALLER. `ReaderEdgeSetup` asks BEFORE anything, because a
// session that is about to drive VoiceOver needs one running; when the probe
// says no it calls `activate()` and asks again.
//
// `activate()` GOES THROUGH A SECOND SEAM, AND THAT IS A REAL CHOICE. Launching
// an application is not an AppleScript question -- routing it through one would
// have meant reaching for a scripting term nobody here has measured, on a
// channel that by definition is not answering. So this class holds a
// ProcessRunner as well, and runs the command that WAS measured:
//
//   MEASURED 2026-08-31: `killall VoiceOver` does NOT relaunch the reader.
//   `open -a VoiceOver` does.
//
// That measurement is why `ReaderCondition`'s recoveries never say "restart
// VoiceOver" on their own: a human who followed a bare `killall` would be left
// with no screen reader. STARTING is all this does. A RESTART takes the reader
// away from somebody who is using it, and no handshake in this bridge may decide
// on one -- the failures name `readerRestartCommand` and a human runs it.
//
// IT SWALLOWS EVERY ERROR, WHICH IS THE PORT'S CONTRACT AND NOT LAZINESS: the
// question is a boolean, its one caller is already handling a failure, and every
// way this can fail -- the grant is gone, the reader is not running, the tool
// could not be launched -- is a "no" as far as that caller is concerned. What
// each of those MEANS is the gesture sender's business, and it has already said
// so by the time this is asked.

import VoiceOverBridgeDomain

public final class VoiceOverLiveness: ReaderLiveness {
	/// VoiceOver's bundle identifier, which is what the running-application list
	/// is keyed by.
	public static let readerBundleIdentifier = "com.apple.VoiceOver"

	/// How the reader is started. `open` is what was measured to work; `killall`
	/// on its own is what was measured NOT to, and nothing here ever kills.
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

	/// Ask the system to start VoiceOver, and answer nothing.
	///
	/// `open` hands the launch to the launch services daemon and returns, so
	/// there is nothing here to report on -- the port says as much, and the only
	/// evidence that counts is `readerIsRunning` afterwards. A failure to
	/// even run the tool is swallowed for the same reason every failure in this
	/// class is: the caller is about to ask the question that actually matters.
	public func activate() {
		_ = try? tools.run(Self.openTool, ["-a", "VoiceOver"])
	}
}
