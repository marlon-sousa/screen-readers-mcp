// ROLE: supporting construct -- the ONE place in this bridge that asks the
// system for the Accessibility grant, shared by the two commands that need it.
//
// USED BY: TypeTextHandler, on a `typeText`; PressGestureHandler, on a batch that
// contains anything at all. DRIVES: the PermissionBroker port.
//
// ============================================================================
// THE LEVER IS SPENT, AND THIS FILE IS WHERE THE RECEIPT GOES.
// ============================================================================
//
// 13.8 built this bridge's one design lever. The two halves of input cost
// different permissions on macOS, so the Accessibility grant could be kept LAZY
// and the claim
//
//     "a session that only presses commands and reads speech never triggers an
//      Accessibility request"
//
// made checkable rather than merely intended. 13.17 narrowed it by one word --
// `pressGesture` took keystrokes as well, and a keystroke is a system event that
// costs the grant exactly as typing does -- leaving
//
//     a session that presses only the reader's COMMAND NAMES and reads speech
//     never triggers an Accessibility request
//
// 13.25 SPENT IT DELIBERATELY, and 13.31 removed the route it named. A VoiceOver
// user presses keys; a command name dispatched inside the reader never passes the
// application under test, so the route that made the lever possible was hiding
// the defect class this tool exists to find. A lever bought by driving the reader
// in a way no user does is bought with the fidelity this tool sells. Spec 0052
// §3.6 states that trade; spec 0055 finishes it.
//
// SO THE CLAIM IS SMALLER AND STILL WORTH KEEPING: nothing but a COMMAND ABOUT TO
// POST AN EVENT ever asks. Not startup, not the handshake -- which reads
// permissions at rung 1 and requests none -- not a probe, and not a test. There
// are exactly two callers of `PermissionBroker.request` in this repository, both
// command handlers, both on the first act of a session that actually needs it, so
// "connecting to this reader never raises a consent dialog" is still checkable and
// still checked.
//
// THIS FILE EXISTS BECAUSE THE SECOND CALLER ARRIVED, which is the same rule
// `HumanWarning` and `Observation` were both created by: a decision that two
// commands must not differ about becomes a file at the entry that creates the
// second caller. Two hand-written copies of a permission check would come to
// differ the first time one of them was reworded, and the thing they would
// differ about is whether somebody's machine raises a consent dialog.
//
// IF YOU ADD A THIRD CALLER, ask first whether the thing you are adding is a
// COMMAND that moves the machine. 13.9 wanted this grant for focus and did not
// take it -- it reads whether the grant is held through an adapter seam that
// cannot request anything -- and that is the shape to copy.

import Foundation

public enum AccessibilityGrant {
	/// Make sure this process may post system events, asking for the grant if it
	/// does not already hold it.
	///
	/// `consequence` is what did NOT happen, in the caller's own words ("nothing
	/// was typed", "nothing was pressed"), because a refusal that does not say
	/// what state the machine is in leaves an agent guessing whether to retry.
	///
	/// `status` FIRST, so a session that already has the grant costs nothing and
	/// raises nothing. A request that does not immediately produce a grant is
	/// reported as NOT YET rather than as a refusal: macOS raises a dialog that
	/// sends the human to System Settings, and they act on it long after this call
	/// has returned. Telling an agent it was refused would send it looking for a
	/// decision nobody has made yet.
	public static func ensure(_ broker: any PermissionBroker, orElse consequence: String) throws {
		guard broker.status(of: .accessibility) != .granted else { return }
		guard broker.request(.accessibility) != .granted else { return }
		// NO ALTERNATIVE ROUTE IS OFFERED, and that is 13.31's doing rather than an
		// omission. This message used to end by pointing at the reader's own command
		// names, which needed no grant; there is no such route now, so the honest
		// answer is that a human has to grant this or nothing can be driven.
		throw CommandError(
			"\(Permission.accessibility.described) A request has been raised on the machine, so if "
				+ "somebody is at it they may be able to grant it now; \(consequence). This bridge "
				+ "drives VoiceOver by pressing the keys a person presses, so there is no route that "
				+ "works without it"
		)
	}
}
