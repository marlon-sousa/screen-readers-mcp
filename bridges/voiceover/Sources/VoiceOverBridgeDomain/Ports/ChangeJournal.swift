// ROLE: port -- the record of every setting on this machine that is currently
// NOT what the person chose, and of every one that has been put back.
//
// IMPLEMENTED BY: FileChangeJournal (adapters) over the FileWriter seam;
// FakeChangeJournal (Tests/Fakes), which records the same entries in memory.
// BUILT BY: Wiring, once per process, and handed to the session in the
// AdapterSet. WRITTEN BY: ReaderEdgeSetup, when it changes something, and
// Session.teardown, when it puts it back. READ BY: nothing in this bridge --
// see below, which is the whole design.
// OWNS: `ReaderChange`, this port's own DTO, in this file per the repo's rule.
//
// ============================================================================
// "IF ALL CHANGED FILES ARE RECORDED IN ONE FILE, WE HAVE OUR PERFECT SNAPSHOT."
// ============================================================================
//
// Marlon, 2026-09-02, and it answers ask 1 of the 2026-09-02 field report
// (`docs/feedback/2026-09-02-acter-run.md`): *"Expose an inventory of everything
// setup touches, and a `restore_reader_settings` call that is safe to run
// blind."*
//
// THE REPORT'S OWN RECOVERY IS THE ARGUMENT FOR THIS FILE EXISTING. A handshake
// failed at `captureProof` with the capture voice left selected -- a voice that
// renders nothing, still selected, on the machine of the person who depends on
// it. Nothing in the MCP could say what had been changed. Putting it back meant
// reading this repository's SOURCE to find out where the selection lives and that
// it must be export-modify-imported rather than written with `defaults`; the hand
// edit that followed DESTROYED the user's pitch, rate and volume and dropped them
// from their premium voice to the compact one, and VoiceOver rebuilt the
// selection on its next start with those values gone.
//
// Every part of that was avoidable by a file saying "this session changed the
// voice from X to Y and has not put it back".
//
// ============================================================================
// FOUR RULES, AND EACH ONE IS A DECISION RATHER THAN A DETAIL.
// ============================================================================
//
// **NOTHING HERE THROWS**, which is `Transcript`'s contract for `Transcript`'s
// reason: a journal that could fail a session would be a record with more power
// than the thing it records, and the thing it records includes the teardown that
// gives a blind person their screen reader back. THE COST IS STATED RATHER THAN
// HIDDEN: a journal that could not be written is a change with no record, and it
// is the one failure in this design with no second line of defence.
//
// **AN OPEN CHANGE IS THE PRODUCT.** A `changed` with no matching `restored` is
// exactly what a crashed session left behind. Everything else in the file is
// history, and history is cheap.
//
// **NOT EVERY CHANGE IS REPAIRABLE BY EDITING SOMETHING**, and `ReaderChange`
// says which are. The modifier PREFERENCE is put back within the handshake
// itself (spec 0053 §3.3); what is ours until teardown is the RUNNING reader's
// in-memory modifier, and the only repair for that is a restart. A tool that
// "fixed" it by writing the file would break the one thing §3.3 got right.
//
// **NOTHING IN THIS BRIDGE READS IT.** The reader is
// `scripts/voiceover_restore.py`, and that asymmetry is deliberate: this file's
// entire audience is somebody -- a human, an agent, a script -- arriving AFTER a
// session that is no longer running. A bridge that consumed its own journal at
// startup would be a bridge undoing another live session's work, and the accept
// loop is serial today but will not always be. That is the same argument that
// keeps `register()` unpaired at teardown.

/// One setting a session changed, or put back.
///
/// A VALUE, not a command: it says what is true, and the file is append-only, so
/// two entries about the same setting are a history rather than a conflict.
public struct ReaderChange: Equatable, Sendable {
	/// What kind of setting this is. A CLOSED SET rather than free text, because
	/// the repair script matches on it and a typo would silently stop repairing
	/// something.
	public enum Kind: String, Equatable, Sendable, CaseIterable {
		/// The voice VoiceOver speaks with, in the system speech domain. THE ONE
		/// A CRASH LEAVES DANGEROUS: it has no expiry, and the next reader restart
		/// finds our voice unpublished, falls back to the system default AND
		/// PERSISTS THE FALLBACK -- so the record of the person's own voice is
		/// destroyed by the recovery rather than by the crash (13.23).
		case voice

		/// The VoiceOver modifier, in VoiceOver's own preference file. Normally
		/// opened and closed WITHIN the handshake -- see the port's header.
		case modifier

		/// The modifier the RUNNING reader is using, which is ours from the
		/// handshake's restart until teardown's. NOT REPAIRABLE BY EDITING
		/// ANYTHING: the file already holds the person's own value, and the only
		/// way back is a reader restart, which their own next restart supplies for
		/// free.
		case runningModifier

		/// Whether a repair tool may put this back by writing a setting.
		public var repairableByWriting: Bool { self != .runningModifier }
	}

	public let kind: Kind

	/// Where the setting lives, in words a human can act on -- a preference domain
	/// and key, or a description for the one that is not a file at all. Recorded
	/// rather than derived, so a repair tool reads a location instead of carrying
	/// a second copy of every path this bridge knows.
	public let store: String

	/// What it was before this session touched it. Nil when there was nothing --
	/// which is an answer, not a gap, and a repair must not invent one.
	public let was: String?

	/// What this session set it to.
	public let now: String?

	public init(kind: Kind, store: String, was: String?, now: String?) {
		self.kind = kind
		self.store = store
		self.was = was
		self.now = now
	}
}

public protocol ChangeJournal: AnyObject {
	/// Record that a setting has been changed. Called AFTER the change succeeded,
	/// because a record of a change that did not happen would send a repair to
	/// undo something nobody did.
	func changed(_ change: ReaderChange)

	/// Record that a setting has been put back. Called AFTER the restore
	/// succeeded, for the mirror of the same reason: a restore recorded
	/// optimistically closes an open change that is still open.
	func restored(_ change: ReaderChange)
}
