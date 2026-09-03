// A hand-written stateful fake for the ReaderModifierStore port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/ReaderModifierStore.swift.
//
// It RECORDS EVERY WRITE IN ORDER, and the order is most of what there is to
// assert: spec 0053 §3.3 is a sequence -- write ours, restart, write theirs back
// -- and a fake that only remembered the last value could not tell that sequence
// from one that never put anything back. `stored` is therefore a list.
//
// IT PAIRS WITH `FakeReaderRestart` IN THE SESSION TESTS, because what has to be
// checked is the INTERLEAVING of the two: the file must hold the person's own
// value again before the handshake returns, not merely by the end of the session.

import VoiceOverBridgeDomain

public final class FakeReaderModifierStore: ReaderModifierStore {
	/// Every value written, in order.
	public private(set) var stored: [ModifierSetting] = []

	/// What the next write does. Set a failure to drive the rung's named refusal
	/// -- a bridge that could not write the modifier must not press keys that mean
	/// nothing on this machine.
	public var failure: ReaderModifierStoreError?

	/// Called on each write, so a test can drive what the READ side answers next
	/// and model a file that really did change.
	public var onStore: ((ModifierSetting) -> Void)?

	public init() {}

	public func store(_ setting: ModifierSetting) throws {
		if let failure { throw failure }
		stored.append(setting)
		onStore?(setting)
	}
}
