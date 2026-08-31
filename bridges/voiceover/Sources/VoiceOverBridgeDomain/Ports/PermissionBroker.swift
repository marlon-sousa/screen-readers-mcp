// ROLE: port -- what this bridge is allowed to do to the machine, and the one
// place it may ASK for more.
//
// IMPLEMENTED BY: TCCPermissionBroker (adapters), a leaf over
// `AXIsProcessTrustedWithOptions`; FakePermissionBroker (Tests/Fakes).
// BUILT BY: Wiring, ONCE PER PROCESS -- the answer is a fact about this process
// and not about a session, and a per-session one would ask the same question
// again for an answer that cannot have changed because a socket was accepted.
// USED BY: the TypeText controller (`request`, and only it), and the launcher's
// startup report (`status`, which asks nobody anything).
//
// THE MACOS-ONLY PORT WITH NO NVDA ANALOGUE, AND THE ENTRY'S WHOLE POINT.
// Windows has no gate on synthesizing a keystroke, so lane 1 has nothing to
// copy and nothing to lose. Here the two halves of input cost DIFFERENT grants
// (spec 0041): pressing one of the reader's own commands is an AppleEvent, and
// typing literal text into whatever holds focus is Accessibility. Keeping them
// apart is what makes
//
//     "a session that only presses commands and reads speech never triggers an
//      Accessibility request"
//
// a CHECKABLE statement about this bridge rather than an intention. The check is
// structural: this port's `request` is reached from the TypeText controller and
// from nowhere else in the bridge -- not from Wiring, not from the adapter
// factory, not from a probe, and not from a test. Wiring CONSTRUCTS the broker
// (construction asks nothing); only `request` raises anything, and only typing
// calls it.
//
// `status` IS A DIFFERENT MATTER AND HAS A SECOND CALLER SINCE 13.10: the
// launcher prints what this process is allowed to do before a run starts. That
// costs nothing and asks nobody -- reading the grant shows no dialog, which is
// the whole reason the two methods are separate.
//
// WHEN THE CONTROL DIALOG LANDS IT BECOMES A SECOND CALLER OF `request`, under a
// human's finger, and the sentence above will have to NARROW rather than die: no
// COMMAND but `typeText` requests anything, and a human pressing a button is not
// a command. That rewrite belongs to the entry that adds the caller -- everywhere
// the claim appears, in the same PR -- because a claim that quietly becomes false
// is worse than one that was never made.
//
// WHY IT IS A DOMAIN PORT HELD BY THE CONTROLLER, AND NOT A COLLABORATOR OF THE
// TYPER -- a layout amendment to spec 0046's 13.8 table, with its why. The spec
// makes this a domain port and then has `AccessibilityTextTyper` hold it, which
// would put a DOMAIN port inside an adapter and make one adapter depend on
// another through a seam the domain owns -- the one thing the layering rule
// forbids. 13.7 met the identical shape with `ReaderLiveness` and went the other
// way: two ports in the AdapterSet, combined by the CONTROLLER. This follows
// that, for a reason 13.7 did not have: the launcher's startup report and the
// control dialog after it need the same
// broker to draw its permission row, and a view may consume a PORT while it may
// not reach through an adapter's private seam. See `TypeTextHandler`.

/// Something the system will not let this process do until a human says so.
///
/// TWO CASES SINCE 13.10, AND THE SECOND ONE ARRIVED WITH SOMETHING THAT READS
/// IT. That is the capability rule applied to an enum: a case whose `status`
/// nothing calls is the same empty promise as a method nothing calls. What reads
/// it is the launcher's startup report, which says what this machine can do
/// before a run starts rather than leaving it to be discovered as a failure ten
/// commands in; the control dialog will read the same value in a row of its own.
/// The gesture sender still learns the answer the other way, from the error the
/// reader returns (`-1743`), which is the right place for a command to learn it
/// and needs no broker at all.
public enum Permission: String, Equatable, Sendable, CaseIterable {
	/// Synthesize input events: `kTCCServiceAccessibility`. What typing costs,
	/// and what pressing one of the reader's own commands deliberately does not.
	case accessibility

	/// Send AppleEvents to VoiceOver: `kTCCServiceAppleEvents`, per target.
	///
	/// EVERY COMMAND IN THIS BRIDGE THAT REACHES THE READER DEPENDS ON IT, which
	/// is why the launcher prints it and why nothing else asks: a gesture, a liveness
	/// check and the VoiceOver-cursor route of `getFocusInfo` all go out over
	/// AppleEvents, and each of them already reports `-1743` in its own words when
	/// the grant is missing. What the row adds is the chance to grant it BEFORE an
	/// agent trips over it, which is a thing only a human at the machine can do.
	case automationVoiceOver

	/// What is not possible without it, in one sentence.
	public var summary: String {
		switch self {
		case .accessibility:
			return "this bridge is not allowed to synthesize keyboard input on this machine"
		case .automationVoiceOver:
			return "this bridge is not allowed to send AppleEvents to VoiceOver on this machine"
		}
	}

	/// What a human has to do about it.
	///
	/// THE SSH WRINKLE IS IN HERE BECAUSE IT IS BAFFLING THE FIRST TIME, and an
	/// agent reading this message is quite likely to be driving the machine from
	/// a remote session. Measured in spec 0041: when the request comes from an
	/// SSH session macOS attributes it to `/usr/libexec/sshd-keygen-wrapper`
	/// rather than to the app that made it, so the consent dialog names something
	/// that looks unrelated to what you were doing -- and granting it grants every
	/// SSH session on the machine, which is a decision worth making deliberately.
	public var recovery: String {
		switch self {
		case .accessibility:
			return
				"grant it under System Settings > Privacy & Security > Accessibility and send the "
				+ "command again. If this bridge was started over SSH, the entry to allow is named "
				+ "/usr/libexec/sshd-keygen-wrapper rather than the app -- macOS attributes the "
				+ "request to the SSH session, and allowing it allows every SSH session on the machine"
		case .automationVoiceOver:
			return
				"allow it when macOS asks, or tick VoiceOver under System Settings > Privacy & "
				+ "Security > Automation for this application. It is not the same switch as "
				+ "VoiceOver's own AppleScript setting, and BOTH are needed: this one is the "
				+ "system's permission to send the reader an event at all, and that one is the "
				+ "reader's willingness to act on it (see Precondition.readerScripting)"
		}
	}

	/// The one rendering an agent gets, so the name and its recovery never travel
	/// apart. Mirrors `ReaderCondition.described`, deliberately: an agent should
	/// not have to learn two shapes for "named condition plus what fixes it".
	public var described: String {
		"\(rawValue): \(summary). Recovery: \(recovery)."
	}
}

/// Whether a permission is in force.
///
/// TWO STATES, NOT THREE, AND THAT IS AN HONEST ANSWER RATHER THAN A COARSE ONE.
/// The Accessibility grant is read through `AXIsProcessTrusted`, which returns a
/// Bool: "not yet asked" and "asked and refused" are the same observable from
/// here. A third case would be a distinction this bridge cannot make, reported
/// as though it could -- and the difference matters to a caller only in what it
/// would say next, which `Permission.recovery` already says for both.
///
/// AND 13.10 DECLINED TO ADD ONE, which is worth recording because this file
/// invited it. `AEDeterminePermissionToAutomateTarget` really does answer three
/// ways for the automation grant -- granted, refused, and not yet asked -- so the
/// row COULD have been three-state. It is not, because the third state would
/// exist for one of the two cases, would have to be rendered as something for the
/// other, and buys the dialog nothing it does not already have: the Request
/// button is offered whenever the answer is not `granted`, and pressing it when
/// the answer was "refused" is how macOS wants a human to be sent to System
/// Settings anyway.
public enum PermissionState: String, Equatable, Sendable {
	case granted
	case notGranted
}

public protocol PermissionBroker: AnyObject {
	/// Whether `permission` is in force. ASKS FOR NOTHING and shows no dialog, so
	/// it is safe to call on any path -- which is what lets the controller check
	/// before it requests, and lets the launcher print what this machine can do
	/// without becoming the thing that triggers a request.
	func status(of permission: Permission) -> PermissionState

	/// Ask the human for `permission`, and report where that left things.
	///
	/// THE ANSWER IS ALMOST ALWAYS `notGranted`, AND THAT IS NOT A FAILURE. macOS
	/// raises a dialog that sends the human to System Settings; they act on it
	/// long after this call has returned, and on some paths the process must be
	/// restarted before the new grant is visible. So `notGranted` here means "not
	/// yet", never "refused", and a caller must say so -- reporting a refusal
	/// would send an agent looking for a decision nobody made.
	///
	/// NEVER THROWS: "it was not granted" IS the answer.
	func request(_ permission: Permission) -> PermissionState
}
