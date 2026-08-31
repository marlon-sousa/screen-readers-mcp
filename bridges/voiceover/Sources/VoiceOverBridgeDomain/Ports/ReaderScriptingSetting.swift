// ROLE: port -- is AppleScript control of VoiceOver switched on on this machine?
//
// IMPLEMENTED BY: VoiceOverPrefsScriptingSetting (adapters), over the PlistReader
// seam; FakeReaderScriptingSetting (Tests/Fakes).
// BUILT BY: Wiring, once per process. USED BY: the launcher's startup report,
// which says what this machine can do before a run starts -- and, when it lands,
// the control dialog's preconditions row.
//
// A DOMAIN PORT CONSUMED BY A DRIVING ACTOR, WHICH IS EXACTLY WHAT ONE MAY DO. A
// launcher and a dialog both consume ports the way a controller does and
// implement none (spec 0011's rule, in its macOS instance). What neither may do
// is reach through an adapter's private seam -- so this is a port, and
// `PlistReader` underneath it is not.
//
// WHY IT IS NOT A `Permission`. Everything in `PermissionBroker` can be ASKED
// FOR: there is an API that raises a dialog and a human who can say yes. This
// cannot. VoiceOver's AppleScript switch lives in VoiceOver Utility > General,
// no API sets it, and the bridge cannot work without it -- which is precisely
// the `Precondition` vocabulary (see the entity), and why that entity exists
// rather than the dialog growing a bespoke row.
//
// THREE ANSWERS, AND THE THIRD ONE IS THE HONEST ONE. The setting is recorded in
// two places on Sequoia (see the adapter), and a machine where neither can be
// read is not a machine where the setting is off -- it is one where this bridge
// does not know. Reporting `disabled` there would send a human to fix a switch
// that may already be on, which is worse than saying so.

/// What the machine says about AppleScript control of VoiceOver.
public enum ScriptingSetting: String, Equatable, Sendable, CaseIterable {
	/// One of the two locations says it is on.
	case enabled

	/// The preferences were readable and say it is off, and the legacy marker is
	/// absent. VoiceOver records only deviations from its defaults, and this
	/// switch ships off -- so "readable, and not mentioned" IS off.
	case disabled

	/// Neither location could be read. Not a fault, and not a `disabled`.
	case unknown
}

public protocol ReaderScriptingSetting: AnyObject {
	/// Read the setting now. Cheap enough to call whenever a human asks the
	/// dialog to refresh, and it changes nothing.
	func scripting() -> ScriptingSetting
}
