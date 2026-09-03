// ROLE: port -- take the reader away and bring it back.
//
// IMPLEMENTED BY: VoiceOverRestart (adapters), over the RunningApplications seam
// and a ProcessRunner; FakeReaderRestart (Tests/Fakes).
// BUILT BY: VoiceOverAdapterFactory. USED BY: ReaderEdgeSetup's modifier rung,
// and Session.teardown -- and nothing else. No command handler may reach it.
//
// ============================================================================
// 13.20 SAID NO HANDSHAKE MAY DO THIS. MARLON REVERSED IT ON 2026-09-02.
// ============================================================================
//
// The rule this port breaks was marked Decided, in these words: *"no handshake in
// this bridge may decide on a restart -- it takes the reader away from somebody
// who is using it."* It is reversed, in these:
//
//   "restarting vo is not a problem for capturing as a bridge handshake, if
//    needed."  -- Marlon, 2026-09-02
//
// Spec 0053 §3.2, and this file is where the reversal is recorded so that nobody
// reads 13.20's sentence somewhere else and re-litigates it.
//
// IT IS ITS OWN PORT RATHER THAN A METHOD ON `ReaderLiveness`, and that is the
// layout consequence of the reversal: liveness answers a QUESTION and this
// performs an ACT with a policy attached. Folding them together would put the
// policy behind a name that reads like a probe.
//
// ============================================================================
// THE BOUNDS ARE THE POINT OF WRITING IT DOWN, AND THEY BIND THE CALLER.
// ============================================================================
//
// * **Only for a named reason.** A capture voice that is registered but not
//   published, or a modifier that had to be replaced. Never speculatively, and
//   never as a way past a failure the bridge cannot explain.
// * **Announced first**, through the bridge's own synthesizer -- which is audible
//   even when the reader is silenced, because it goes around the reader entirely
//   (13.10). Nobody is dropped into silence unwarned. That is the CALLER's
//   obligation: this port makes no sound.
// * **Quit, WAIT for the process to be gone, then open.** See below.
//
// ============================================================================
// THE SEQUENCE IS THE WHOLE IMPLEMENTATION, AND EVERY PART OF IT WAS MEASURED.
// ============================================================================
//
// `killall VoiceOver && open -a VoiceOver` -- which this repository printed as a
// recovery instruction for weeks -- is WRONG IN TWO WAYS, and both of them were
// paid for on the maintainer's own machine:
//
//   * `killall` ALONE does not relaunch the reader (measured 2026-08-31). A human
//     who ran only the first half was left with no screen reader at all.
//   * The `&&` ONE-LINER RACES. `killall` returns as soon as the signal is sent,
//     not when the process is gone, so `open -a` can fire while VoiceOver is
//     still shutting down -- and `open` on an application the system still
//     believes is running does nothing at all. That is very probably what the
//     2026-09-02 field report hit: following this repository's own advice left
//     the reader in a state where every scripting call answered `-1728`, and it
//     cost about twenty minutes and an interruption of the blind user at the
//     machine before Command-F5 fixed it.
//
// So an implementation quits, POLLS until the process is actually gone, and only
// then starts it -- and it reports which of those steps failed, because "the
// reader did not come back" is the one failure here that a person is living
// inside while they read it.
//
// IT IS THE ONE RUNG 13.20 COULD NOT CLIMB. A newly registered capture voice is
// published only after the reader restarts, so `registered` -> `published` was a
// failure that named a command for a human to run. It is a step now.

/// A restart that did not complete.
///
/// Its own type rather than the command layer's `CommandError`, because a port
/// may not depend on a controller. It carries which half failed, because the
/// recoveries are opposite: a reader that would not quit is an inconvenience, and
/// a reader that would not come back is a person with no screen reader.
public struct ReaderRestartError: Error, Equatable, CustomStringConvertible {
	public let description: String

	/// Whether the reader is believed to be RUNNING despite the failure.
	///
	/// THE FIELD EXISTS SO A CALLER CAN SAY THE RIGHT THING TO A HUMAN WHO MAY BE
	/// SITTING IN SILENCE. "I could not stop VoiceOver" leaves them with a working
	/// reader; "I stopped VoiceOver and it did not come back" does not, and those
	/// two sentences must never be interchangeable.
	public let readerStillRunning: Bool

	public init(_ description: String, readerStillRunning: Bool) {
		self.description = description
		self.readerStillRunning = readerStillRunning
	}
}

public protocol ReaderRestart: AnyObject {
	/// Quit the reader, wait for it to be gone, and start it again.
	///
	/// BLOCKS UNTIL IT IS BACK, or throws. There is no asynchronous half: every
	/// caller's next act depends on a reader that has re-read its preferences, and
	/// a method that returned before that would hand back a machine in the state
	/// the caller was trying to leave.
	///
	/// SAYING NOTHING IS THE CALLER'S JOB TO FIX. This port makes no sound; the
	/// announcement that must precede a restart belongs to the controller, which
	/// is the only thing that holds the announcer and knows why it is restarting.
	func restart() throws
}
