// ROLE: port -- SET the VoiceOver modifier on this machine.
//
// IMPLEMENTED BY: VoiceOverPrefsModifierStore (adapters), over the PlistReader
// and PlistWriter seams; FakeReaderModifierStore (Tests/Fakes).
// BUILT BY: Wiring, once per process, and handed to the session in the
// AdapterSet. USED BY: ReaderEdgeSetup's modifier rung, and NOTHING ELSE -- no
// command handler may reach it.
//
// ============================================================================
// IT IS THE WRITE SIDE, AND IT IS A SEPARATE PORT FROM THE READ SIDE ON PURPOSE.
// ============================================================================
//
// `ReaderModifierSetting` answers what the person chose; this changes it. They
// are separated for exactly the reason `PermissionBroker` separates `status` from
// `request`: one of them looks at somebody's machine and the other one edits it,
// and a caller that only ever needed to look must not be holding the thing that
// can write. `VoiceOverPrefsModifierSetting`'s header carries the sentence "IT
// NEVER WRITES", and this port is what keeps that true rather than aspirational.
//
// IT DOES NOT READ, and that is a deliberate narrowing of spec 0053 §4's first
// draft, which had this port do both. Rung 1 has already read the modifier
// through `ReaderModifierSetting` before this is ever called, and two ports
// answering one question are two answers waiting to differ about which keys to
// press at somebody's screen reader.
//
// ============================================================================
// WHY THIS EXISTS AT ALL -- 13.26, AND IT IS A SESSION LOAN RATHER THAN AN EDIT.
// ============================================================================
//
// Where `vo` is bound to Caps Lock alone, this bridge cannot press it: a
// synthesized Caps Lock is invisible to the reader, measured 2026-09-02 four
// different ways, and the platform explains it -- Caps Lock is a system-level
// toggle, and posting `.maskAlphaShift` reports that it is down without making
// the system believe it. So a Caps-Lock machine had no key route at all, and
// with the AppleScript switch off it had no route of any kind.
//
// THE ORDER THE CALLER USES IS WHAT MAKES THIS SAFE, and it is spec 0053 §3.3:
//
//   1. read the person's setting;
//   2. write ours, and RESTART -- the running reader is now on ours;
//   3. IMMEDIATELY write the person's setting back into the file;
//   4. at teardown, restart so the reader is on their own modifier again.
//
// So the FILE never holds our value for longer than a moment. A session that dies
// without tearing down costs "the reader is on Control-Option until it next
// restarts", and the person's own next restart puts it right with nothing to
// remember. Keeping our value in the file until teardown would have left a WRONG
// STORED PREFERENCE SURVIVING REBOOTS, which is worse than the dangling capture
// voice this lane already paid for and has no self-correction at all.
//
// AND THE READER READS IT ONLY AT STARTUP, which is why a restart is part of the
// sequence rather than an optimisation. Measured 2026-09-02: writing the file and
// pressing `control+option+d` with Marlon listening produced nothing; restarting
// and pressing it again produced "we are in dock".

/// A modifier that could not be stored.
///
/// Its own type rather than the command layer's `CommandError`, because a port
/// may not depend on a controller. `ReaderEdgeSetup` translates it into a named
/// rung failure.
public struct ReaderModifierStoreError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol ReaderModifierStore: AnyObject {
	/// Write `setting` as the machine's VoiceOver modifier, and confirm it landed.
	///
	/// THROWING IS THE CONTRACT AND SO IS THE CONFIRMATION. A write that silently
	/// did not take is how spec 0047's finding 17 happened -- the preference was
	/// rewritten from a cache before anybody looked, and "writing does nothing"
	/// was recorded as a fact for weeks. An implementation reads the key back and
	/// throws when it is not what it wrote.
	///
	/// `.unknown` IS NOT A VALUE THIS CAN STORE and an implementation refuses it
	/// by name. It is the answer "I could not read the file", and writing it would
	/// mean inventing a modifier for somebody.
	///
	/// IT MUST NOT LOSE THE REST OF THE FILE. VoiceOver keeps around 120 settings
	/// there -- pitch, rate, voice, Quick Nav, the lot -- and an implementation
	/// that replaced the domain rather than editing one key of it would take all
	/// of them with it. See the adapter, which counts the keys either side and
	/// treats a DROP as a failure.
	func store(_ setting: ModifierSetting) throws
}
