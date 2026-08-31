// ROLE: port -- what this bridge is allowed to do to the machine, and the one
// place it may ASK for more.
//
// IMPLEMENTED BY: TCCPermissionBroker (adapters), over `AXIsProcessTrusted` for
// one permission and over the AppleScript channel for the other -- see below,
// because which mechanism answers which is not an implementation detail here;
// FakePermissionBroker (Tests/Fakes).
// BUILT BY: Wiring, ONCE PER PROCESS -- the answer is a fact about this process
// and not about a session, and a per-session one would ask the same question
// again for an answer that cannot have changed because a socket was accepted.
// USED BY: the TypeText controller (`request`, and only it), and the launcher's
// startup report (`status`, which asks nobody anything).
//
// THE TWO PERMISSIONS ARE READ BY DIFFERENT MEANS, AND 13.11 HAD TO FIX THAT
// AFTER 13.10 SHIPPED IT WRONG. The distinction is structural rather than
// incidental:
//
//   * ACCESSIBILITY is a fact about THIS PROCESS, which posts its own CGEvents.
//     `AXIsProcessTrusted` answers about the caller, and the caller is the one
//     that acts. The API and the actor agree.
//   * AUTOMATION is a fact about A CHANNEL. This bridge never sends an AppleEvent
//     itself: every one leaves a `/usr/bin/osascript` subprocess, and macOS
//     attributes a subprocess's events to whatever process it holds RESPONSIBLE
//     for it -- the app bundle when the bridge runs as one, and whatever launched
//     it when it does not. So an API that answers about the calling binary is
//     answering about a process that sends nothing.
//
// MEASURED 2026-08-30, and it is the reason this header changed. On the
// maintainer's machine, seconds apart:
// `AEDeterminePermissionToAutomateTarget(com.apple.VoiceOver, askUserIfNeeded:
// false)` returned **-1744** (`errAEEventWouldRequireUserConsent`) from an
// unsigned launcher binary -- reported as `notGranted` -- while that same
// process's `osascript` had just driven the reader successfully through a whole
// MCP session. The startup report therefore printed a FALSE NEGATIVE about a
// machine that was working. The grant was held all along, by the responsible
// process: VS Code was launched over SSH, Claude Code from VS Code, and the
// bridge from Claude Code, so the identity TCC consulted was
// `/usr/libexec/sshd-keygen-wrapper`, which the maintainer had granted.
//
// SO `status(.automationVoiceOver)` ASKS THE CHANNEL, by sending the same
// `return name` probe every gesture route uses, and reads the NUMBER: `-1743`
// (`errAEEventNotPermitted`) IS the missing grant, a reply IS the grant, and
// anything else is `cannotTell` rather than a guess. See TCCPermissionBroker.
//
// THE CASE WAS KEPT RATHER THAN DELETED, and the alternative is worth recording
// because this file's own header proposed it before 13.10: `automationVoiceOver`
// could have been removed, leaving `Permission` a fact about this process alone.
// It is kept because the grant IS a thing a human can be asked for -- which is
// what makes it a `Permission` and not a `Precondition` -- because `recovery`'s
// prose is what a human acts on, and because the control dialog (13.14) needs the
// row with a Request behind it. What was wrong was the READING, not the concept.
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
	///
	/// IT IS THE PERMISSION OF THE RESPONSIBLE PROCESS, NOT OF THIS BINARY, which
	/// is why reading it costs a subprocess and why it is the one permission that
	/// can answer `cannotTell`. The header carries the measurement.
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
/// THREE STATES SINCE 13.11, AND THE THIRD ONE IS NOT THE ONE 13.10 DECLINED.
/// That distinction matters, because this file has now been asked for a third
/// case twice and only one of the two requests was worth granting.
///
/// WHAT WAS DECLINED, AND STAYS DECLINED: "refused" versus "not yet asked".
/// `AEDeterminePermissionToAutomateTarget` really does separate them, and
/// `AXIsProcessTrusted` does not. It is still not modelled, because what a caller
/// DOES about them is identical -- offer the human the request -- and
/// `Permission.recovery` already says the same sentence for both.
///
/// WHAT WAS ADDED, AND WHY IT IS A DIFFERENT QUESTION: `cannotTell` does not
/// refine "not granted", it refuses to answer at all. The automation grant is
/// read by USING the channel (see PermissionBroker's header), and a channel can
/// fail for reasons that say nothing whatever about a permission -- the reader is
/// not running, `osascript` could not be launched, the scripting object model is
/// wedged. Reporting any of those as `notGranted` would send a human to System
/// Settings to fix a grant they already hold, which is precisely the false
/// negative 13.11 exists to remove; reporting them as `granted` would promise a
/// channel nobody tested. So the honest answer is that this cannot be determined
/// from here, and the launcher prints it as that.
///
/// ONLY ONE PERMISSION CAN BE IN IT, and that asymmetry is real rather than
/// sloppy: Accessibility is answered by an API about this process, which always
/// answers. A caller that treats `cannotTell` as "not granted" is not wrong about
/// what to show; it is wrong about what to blame.
public enum PermissionState: String, Equatable, Sendable {
	case granted
	case notGranted

	/// The channel that would answer this did not, for a reason that is not a
	/// permission. Never returned for `.accessibility`.
	case cannotTell
}

public protocol PermissionBroker: AnyObject {
	/// Whether `permission` is in force. ASKS FOR NOTHING and shows no dialog, so
	/// it is safe to call on any path -- which is what lets the controller check
	/// before it requests, and lets the launcher print what this machine can do
	/// without becoming the thing that triggers a request.
	///
	/// IT IS NOT FREE FOR EVERY PERMISSION, SINCE 13.11: reading the automation
	/// grant means using the channel, which is a subprocess. Cheap enough for a
	/// startup report and for a dialog a human refreshes; not cheap enough to put
	/// in front of a command, which is why no command calls it.
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
