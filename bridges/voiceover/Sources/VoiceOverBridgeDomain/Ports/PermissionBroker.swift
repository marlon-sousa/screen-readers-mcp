// ROLE: port -- what this bridge is allowed to do to the machine, and the one
// place it may ASK for more.
//
// IMPLEMENTED BY: TCCPermissionBroker (adapters), a leaf over
// `AXIsProcessTrustedWithOptions`; FakePermissionBroker (Tests/Fakes).
// BUILT BY: Wiring, ONCE PER PROCESS -- the answer is a fact about this process
// and not about a session, and a per-session one would ask the same question
// again for an answer that cannot have changed because a socket was accepted.
// USED BY: the TypeText controller, and from 13.10 the dialog's permission row.
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
// structural: this port is reached from the TypeText controller and from nowhere
// else in the bridge -- not from Wiring, not from the adapter factory, not from
// a probe, and not from a test. Wiring CONSTRUCTS the broker (construction asks
// nothing); only `request` raises anything, and only typing calls it.
//
// WHY IT IS A DOMAIN PORT HELD BY THE CONTROLLER, AND NOT A COLLABORATOR OF THE
// TYPER -- a layout amendment to spec 0046's 13.8 table, with its why. The spec
// makes this a domain port and then has `AccessibilityTextTyper` hold it, which
// would put a DOMAIN port inside an adapter and make one adapter depend on
// another through a seam the domain owns -- the one thing the layering rule
// forbids. 13.7 met the identical shape with `ReaderLiveness` and went the other
// way: two ports in the AdapterSet, combined by the CONTROLLER. This follows
// that, for a reason 13.7 did not have and 13.10 does: the dialog needs the same
// broker to draw its permission row, and a view may consume a PORT while it may
// not reach through an adapter's private seam. See `TypeTextHandler`.

/// Something the system will not let this process do until a human says so.
///
/// ONE CASE TODAY, AND THAT IS THE CAPABILITY RULE APPLIED TO AN ENUM. Spec
/// 0046's table names `automationVoiceOver` beside it, for the dialog row that
/// says whether AppleEvents to VoiceOver are allowed -- and nothing in this
/// build asks that question: the gesture sender learns it from the error the
/// reader returns (`-1743`), which is the right place and needs no broker. A
/// case whose `status` nothing calls is the same promise as a method nothing
/// calls, so it arrives with 13.10, beside the row that reads it.
public enum Permission: String, Equatable, Sendable, CaseIterable {
	/// Synthesize input events: `kTCCServiceAccessibility`. What typing costs,
	/// and what pressing one of the reader's own commands deliberately does not.
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
/// TWO STATES, NOT THREE, AND THAT IS AN HONEST ANSWER RATHER THAN A COARSE ONE.
/// The Accessibility grant is read through `AXIsProcessTrusted`, which returns a
/// Bool: "not yet asked" and "asked and refused" are the same observable from
/// here. A third case would be a distinction this bridge cannot make, reported
/// as though it could -- and the difference matters to a caller only in what it
/// would say next, which `Permission.recovery` already says for both. If 13.10's
/// automation row needs the three-way answer `AEDeterminePermissionToAutomateTarget`
/// gives, it can add one THEN, beside the thing that can observe it.
public enum PermissionState: String, Equatable, Sendable {
	case granted
	case notGranted
}

public protocol PermissionBroker: AnyObject {
	/// Whether `permission` is in force. ASKS FOR NOTHING and shows no dialog, so
	/// it is safe to call on any path -- which is what lets the controller check
	/// before it requests, and lets 13.10's dialog draw a row without becoming the
	/// thing that triggers the request.
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
