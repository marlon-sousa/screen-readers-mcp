// ROLE: port -- is the reader RUNNING at all?
//
// IMPLEMENTED BY: VoiceOverLiveness (adapters), over the RunningApplications
// seam; FakeReaderLiveness (Tests/Fakes).
// BUILT BY: VoiceOverAdapterFactory. USED BY: ReaderEdgeSetup's rung 2, before
// anything is asked of the reader; and the PressGesture handler, ONLY after a
// dispatch has already failed.
//
// ============================================================================
// IT ASKED BY APPLEEVENT UNTIL 13.26, AND WHAT THAT COST WAS A PERMISSION.
// ============================================================================
//
// The old question was "does the reader answer its OWN NAME" -- `tell application
// "VoiceOver" to return name`, an application-level property chosen because it
// answers even when the scripting object model is dead, which is the state spec
// 0041 measured: after six consecutive commands every VoiceOver call began
// failing silently while the process ran and answered its name. That worked.
//
// What it cost is that liveness could not be established without the AUTOMATION
// grant, on a machine intending to drive the reader entirely by keystrokes. And
// 13.26's requirement is sharper than convenience: "Allow VoiceOver to be
// controlled with AppleScript" lets ANY process drive the screen reader a blind
// person depends on, so every use of that channel has to justify itself, and this
// one could not. The running-application list answers the same question at NO
// permission cost, cannot be switched off, and is exact where the AppleEvent was
// a proxy. Spec 0053 §3.7.
//
// SPEC 0041's DISTINCTION IS NOT LOST -- IT MOVED UP, AND IT GOT WIDER. "The
// reader is there but the command failed" is now composed by the CALLER from this
// answer AND the AppleScript switch's state, which separates THREE conditions
// where the old probe separated two:
//
//   1. nothing is running                       -> the reader is gone; start it
//   2. running, and the switch is off/unreadable -> that route is not offered
//                                                   here; press the key instead
//   3. running, the switch is on, still failed   -> the object model is dead,
//                                                   and a restart repairs it
//
// The second was a SHIPPED DEFECT until 13.26: with the switch off, `perform
// command` fails with `-1728`/`-1708`, which is EXACTLY what a wedged reader
// answers, so the bridge told a blind person to restart their screen reader to
// repair a switch they had deliberately turned off. See PressGestureHandler.explain.
//
// WHAT IT MUST NOT BE READ AS -- MEASURED 2026-08-30, AND IT COST AN EVENING.
// There is a FOURTH condition that looks like all of the above from the outside:
// the APPLICATION UNDER TEST is wedged while the reader is entirely healthy. On
// the maintainer's machine Finder stopped responding, every cursor read answered
// `missing value`, dispatches appeared to do nothing -- and VoiceOver was fine,
// saying so out loud in the user's own language. `killall Finder` fixed it.
// Nothing on this port can detect that, and nothing here should pretend to: it
// answers one narrow question about the READER, and a healthy answer from it is
// not a claim that the machine under test is healthy. Spec 0047's finding 5 is
// the same confound approached from the other end.
public protocol ReaderLiveness: AnyObject {
	/// Whether the reader's process is running on this machine.
	///
	/// NEVER THROWS. "It is not there" IS the answer, and an error here would
	/// force a caller -- one of which is already handling a failure -- to handle a
	/// second one in order to learn a boolean.
	///
	/// IT IS NOT A CLAIM THAT THE READER IS WELL. A process can be running with
	/// its scripting object model dead (spec 0041) and running while it ignores
	/// synthesized key events (13.22's live run). Those are separate conditions
	/// with separate recoveries, and the CALLER names them -- see the header.
	func readerIsRunning() -> Bool

	/// Ask the machine to start the reader. ADDED AT 13.20.
	///
	/// A SECOND CALLER ARRIVED AND IT ASKS THE OPPOSITE QUESTION. Everything in
	/// this file's header is about a probe asked AFTER a failure; the handshake
	/// asks BEFORE anything, because a session that is about to drive VoiceOver
	/// needs one running. When the probe says no, `ReaderEdgeSetup` calls this
	/// and asks again.
	///
	/// NEVER THROWS, AND ANSWERS NOTHING, which is the whole shape of it: this is
	/// a REQUEST, and the only evidence that counts is `readerIsRunning`
	/// afterwards. An implementation that returned "it worked" would be reporting
	/// on a launch it cannot have observed yet -- macOS hands `open` to the
	/// launch services daemon and returns.
	///
	/// IT STARTS, AND A RESTART IS A DIFFERENT PORT -- `ReaderRestart`, since
	/// 13.26. Activating the reader is what a person's own Command-F5 does, it
	/// announces itself out loud, and a session needs it. Taking a running reader
	/// AWAY from somebody is an act with a policy attached (announce first; quit,
	/// wait for the process to be gone, then open), and a port that answers a
	/// question is the wrong place for it.
	///
	/// **13.20's rule that no handshake may restart the reader was REVERSED by
	/// Marlon on 2026-09-02** -- *"restarting vo is not a problem for capturing as
	/// a bridge handshake, if needed"* -- and this comment used to state it as
	/// settled. It is spec 0053 §3.2 now, with its bounds. Nothing about THIS
	/// method changed: it still only ever starts.
	///
	/// MEASURED 2026-08-31: `killall VoiceOver` does not relaunch the reader;
	/// `open -a VoiceOver` does. See VoiceOverLiveness.
	func activate()
}
