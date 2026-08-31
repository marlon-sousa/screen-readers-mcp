// ROLE: supporting construct -- the ONE place in this bridge that asks the
// system for the Accessibility grant, shared by the two commands that need it.
//
// USED BY: TypeTextHandler, on a `typeText`; PressGestureHandler, on a batch
// that contains a KEYSTROKE. DRIVES: the PermissionBroker port.
//
// ============================================================================
// THE LEVER, AS IT STANDS AFTER 13.17, AND WHY IT IS STILL WORTH SOMETHING.
// ============================================================================
//
// 13.8 built this bridge's one design lever: the two halves of input cost
// different permissions on macOS, so the Accessibility grant could be kept LAZY
// and the claim
//
//     "a session that only presses commands and reads speech never triggers an
//      Accessibility request"
//
// made checkable rather than merely intended. Windows has no equivalent gate, so
// lane 1 has no analogue and there was nothing to copy.
//
// 13.17 NARROWED IT BY ONE WORD, AND DID NOT SPEND IT. `pressGesture` now takes
// keystrokes as well as command names, and a keystroke is a system event that
// costs the grant exactly as typing does. So the claim is now:
//
//     a session that presses only the reader's COMMAND NAMES and reads speech
//     never triggers an Accessibility request
//
// -- which is the property that was ever worth having, and the one the
// counting-broker scenario in Tests/Integration/SessionRoundTripTests.swift
// asserts end to end. What did NOT happen is a bridge that asks at startup, at
// the handshake, from a probe or from a test. There are exactly two callers of
// `PermissionBroker.request` in this repository, both of them command handlers,
// both on the first act of a session that actually needs it.
//
// THIS FILE EXISTS BECAUSE THE SECOND CALLER ARRIVED, which is the same rule
// `HumanWarning` and `Observation` were both created by: a decision that two
// commands must not differ about becomes a file at the entry that creates the
// second caller. Two hand-written copies of a permission check would come to
// differ the first time one of them was reworded, and the thing they would
// differ about is whether somebody's machine raises a consent dialog.
//
// IF YOU ADD A THIRD CALLER, YOU HAVE PROBABLY SPENT THE LEVER. Ask first
// whether the thing you are adding is a COMMAND that moves the machine. 13.9
// wanted this grant for focus and did not take it -- it reads whether the grant
// is held through an adapter seam that cannot request anything -- and that is
// the shape to copy.

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
		throw CommandError(
			"\(Permission.accessibility.described) A request has been raised on the machine, so if "
				+ "somebody is at it they may be able to grant it now; \(consequence). Pressing the "
				+ "reader's own COMMAND NAMES with `pressGesture` -- \"go to desktop\" rather than "
				+ "\"command+l\" -- needs no such grant and still works"
		)
	}
}
