// A hand-written stateful fake for the ChangeJournal port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/ChangeJournal.swift.
//
// It keeps the entries IN ORDER and in one list rather than two, because the
// thing worth asserting is a PAIRING: a `changed` with no matching `restored` is
// what a crashed session leaves behind, and that is the whole product. Two lists
// would make the interleaving unassertable, which is exactly the property the
// journal exists to record.
//
// `open` IS THE QUESTION A REPAIR TOOL ASKS, so the fake answers it here rather
// than making every test re-derive it.

import VoiceOverBridgeDomain

public final class FakeChangeJournal: ChangeJournal {
	/// One entry per call, in order, saying which verb it was.
	public struct Entry: Equatable, Sendable {
		public let change: ReaderChange
		public let restored: Bool
	}

	public private(set) var entries: [Entry] = []

	public init() {}

	public func changed(_ change: ReaderChange) {
		entries.append(Entry(change: change, restored: false))
	}

	public func restored(_ change: ReaderChange) {
		entries.append(Entry(change: change, restored: true))
	}

	/// The kinds that were changed and never put back -- what a repair tool acts
	/// on, and what a test asserting "this session cleaned up after itself" wants.
	public var openKinds: [ReaderChange.Kind] {
		var open: [ReaderChange.Kind] = []
		for entry in entries {
			if entry.restored {
				open.removeAll { $0 == entry.change.kind }
			} else if !open.contains(entry.change.kind) {
				open.append(entry.change.kind)
			}
		}
		return open
	}
}
