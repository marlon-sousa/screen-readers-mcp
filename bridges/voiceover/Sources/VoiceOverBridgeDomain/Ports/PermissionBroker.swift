// ROLE: port -- what this bridge is allowed to do to the machine, and the one
// place it may ASK for more.
//
// IMPLEMENTED BY: TCCPermissionBroker (adapters), over `AXIsProcessTrusted`;
// FakePermissionBroker (Tests/Fakes).
// BUILT BY: Wiring, ONCE PER PROCESS -- the answer is a fact about this process
// and not about a session, and a per-session one would ask the same question
// again for an answer that cannot have changed because a socket was accepted.
// USED BY: the TypeText and PressGesture controllers (`request`, and only them),
// ReaderEdgeSetup's first rung and the launcher's startup report (`status`, which
// asks nobody anything).
//
// ============================================================================
// ONE PERMISSION SINCE 13.31. IT HELD TWO, AND THE SECOND WENT WITH ITS CHANNEL.
// ============================================================================
//
// `automationVoiceOver` was the grant to send AppleEvents to VoiceOver, and this
// bridge sends none: the command-name route was deleted at 13.31 because no
// VoiceOver user can type a command name, and it was the only thing that needed
// the grant (spec 0055). The case is gone rather than kept as a row nothing acts
// on -- a permission whose absence stops nothing is a permission this bridge has
// no business asking a human about.
//
// WHAT WENT WITH IT IS WORTH RECORDING, because it was hard-won and is now moot.
// The two grants were read by DIFFERENT MEANS, and 13.11 had to fix that after
// 13.10 shipped it wrong: Accessibility is a fact about THIS PROCESS, which posts
// its own CGEvents, so `AXIsProcessTrusted` answers about the caller and the
// caller is the one that acts -- while Automation was a fact about A CHANNEL,
// because every AppleEvent left a `/usr/bin/osascript` subprocess and macOS
// attributes a subprocess's events to whatever process it holds RESPONSIBLE for
// it. Measured 2026-08-30: `AEDeterminePermissionToAutomateTarget` returned
// `-1744` from the launcher binary while that same process's `osascript` had just
// driven the reader through a whole MCP session, because the identity TCC
// consulted was `/usr/libexec/sshd-keygen-wrapper` over SSH. That asymmetry is why
// `PermissionState` had a `cannotTell`, and why it no longer does: the one
// permission left is answered by an API about this process, and that API always
// answers.
//
// THE MACOS-ONLY PORT WITH NO NVDA ANALOGUE. Windows has no gate on synthesizing
// a keystroke, so lane 1 has nothing to copy and nothing to lose. Here, pressing
// what a person presses costs `kTCCServiceAccessibility` -- and since 13.31 that
// is what driving this reader IS, so the grant is no longer a thing a session can
// avoid by choosing a route.
//
// ============================================================================
// 13.8's LEVER IS SPENT, AND THIS IS WHERE IT WAS RECORDED, SO THIS IS WHERE IT
// IS BURIED.
// ============================================================================
//
// The claim used to be that
//
//     a session that presses only the reader's COMMAND NAMES and reads speech
//     never triggers an Accessibility request
//
// was a CHECKABLE statement about this bridge rather than an intention. It was
// true, it was checked, and 13.25 spent it deliberately: a lever bought by driving
// the reader in a way no user does is bought with the fidelity this tool sells.
// 13.31 removed the route it described, so the sentence now describes a session
// that presses nothing at all -- and a claim that has quietly become vacuous is
// worse than one that was never made, which is why it is struck here rather than
// narrowed a third time.
//
// WHAT SURVIVES IS THE STRUCTURAL PART, and it is worth as much as it ever was:
// this port's `request` is reached from TWO COMMAND HANDLERS and from nowhere else
// -- not from Wiring, not from the adapter factory, not from a probe, not from a
// test, and NOT from the handshake, which reads every permission it needs and
// requests none. Wiring CONSTRUCTS the broker (construction asks nothing); only
// `request` raises anything, and only a command that is about to post a system
// event calls it, through `AccessibilityGrant`. So "connecting to this reader
// never raises a consent dialog" is still a checkable sentence, and the tests
// still check it.
//
// WHEN THE CONTROL DIALOG LANDS IT BECOMES A THIRD CALLER OF `request`, under a
// human's finger. That is not a command, and the rewrite belongs to the entry that
// adds the caller.
//
// WHY IT IS A DOMAIN PORT HELD BY THE CONTROLLER, AND NOT A COLLABORATOR OF THE
// TYPER -- a layout amendment to spec 0046's 13.8 table, with its why. The spec
// makes this a domain port and then has `AccessibilityTextTyper` hold it, which
// would put a DOMAIN port inside an adapter and make one adapter depend on
// another through a seam the domain owns -- the one thing the layering rule
// forbids. 13.7 met the identical shape with `ReaderLiveness` and went the other
// way: two ports in the AdapterSet, combined by the CONTROLLER. This follows
// that, for a reason 13.7 did not have: the launcher's startup report and the
// control dialog after it need the same broker to draw its permission row, and a
// view may consume a PORT while it may not reach through an adapter's private
// seam. See `TypeTextHandler`.

/// Something the system will not let this process do until a human says so.
///
/// ONE CASE SINCE 13.31, AND AN ENUM IS STILL THE RIGHT SHAPE. A case whose
/// `status` nothing calls is the same empty promise as a method nothing calls, so
/// `automationVoiceOver` went when the channel that needed it did (see the
/// header). This stays an enum rather than collapsing into a bare boolean because
/// `summary` and `recovery` are the vocabulary a human acts on, because the
/// control dialog draws a row per case, and because this is where a second
/// permission would arrive if macOS ever gated something else this bridge does.
public enum Permission: String, Equatable, Sendable, CaseIterable {
	/// Synthesize input events: `kTCCServiceAccessibility`. What typing costs, and
	/// -- since 13.25 made keys the way this bridge drives the reader -- what
	/// pressing a gesture costs too.
	case accessibility

	/// What is not possible without it, in one sentence.
	public var summary: String {
		switch self {
		case .accessibility:
			return "this bridge is not allowed to synthesize keyboard input on this machine"
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
/// TWO STATES SINCE 13.31, AND IT HAS BEEN ASKED FOR A THIRD TWICE. Neither
/// request applies any more, and both are worth recording so a third does not
/// arrive by accident.
///
/// WHAT WAS DECLINED, AND STAYS DECLINED: "refused" versus "not yet asked".
/// `AEDeterminePermissionToAutomateTarget` really did separate them, and
/// `AXIsProcessTrusted` does not. It is still not modelled, because what a caller
/// DOES about them is identical -- offer the human the request -- and
/// `Permission.recovery` already says the same sentence for both.
///
/// WHAT WAS ADDED AT 13.11 AND REMOVED AT 13.31: `cannotTell`, which did not
/// refine "not granted" but refused to answer at all. It existed because the
/// automation grant was read by USING a channel, and a channel can fail for
/// reasons that say nothing whatever about a permission -- the reader not running,
/// `osascript` not launching, the scripting object model wedged. There is no such
/// channel now: the one permission left is answered by an API about this process,
/// which always answers, so a state nothing can return is gone rather than left as
/// a case every caller has to handle and no test can reach.
public enum PermissionState: String, Equatable, Sendable {
	case granted
	case notGranted
}

public protocol PermissionBroker: AnyObject {
	/// Whether `permission` is in force. ASKS FOR NOTHING and shows no dialog, so
	/// it is safe to call on any path -- which is what lets the controller check
	/// before it requests, and lets the launcher print what this machine can do
	/// without becoming the thing that triggers a request.
	///
	/// AND IT IS FREE AGAIN SINCE 13.31. It was not, between 13.11 and this entry:
	/// reading the automation grant meant using the channel, which is a subprocess
	/// -- cheap enough for a startup report and not cheap enough to put in front of
	/// a command. The remaining permission is one `AXIsProcessTrusted` call, so the
	/// only reason no command calls this on its hot path is that no command needs
	/// to.
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
