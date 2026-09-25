import VoiceOverBridgeDomain

public final class FakeChangeJournal: ChangeJournal {
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
