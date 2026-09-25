// ROLE: port -- the record of every setting on this machine a session changed, and of every one put back.
// IMPLEMENTED BY: FileChangeJournal, over the FileWriter seam; FakeChangeJournal.
// BUILT BY: Wiring, once per process, and handed to the session in the AdapterSet.
// USED BY: ReaderEdgeSetup and Session.teardown write it; only scripts/voiceover_restore.py reads it.
// Nothing here throws, so the journal can never fail a teardown; an unwritable journal leaves a change unrecorded.
// Nothing in this bridge reads it: consuming it at startup could undo another live session's work.

public struct ReaderChange: Equatable, Sendable {
	/// A closed set, because the repair script matches on it.
	public enum Kind: String, Equatable, Sendable, CaseIterable {
		/// Dangerous after a crash: the next reader restart persists the system default over the person's own voice.
		case voice
	}

	public let kind: Kind

	public let store: String

	/// Nil means there was nothing, and a repair must not invent one.
	public let was: String?

	public let now: String?

	public init(kind: Kind, store: String, was: String?, now: String?) {
		self.kind = kind
		self.store = store
		self.was = was
		self.now = now
	}
}

public protocol ChangeJournal: AnyObject {
	/// Call only after the change succeeded.
	func changed(_ change: ReaderChange)

	/// Call only after the restore succeeded.
	func restored(_ change: ReaderChange)
}
