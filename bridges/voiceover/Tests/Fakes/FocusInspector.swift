// A hand-written stateful fake for the FocusInspector port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/FocusInspector.swift.
//
// It answers a snapshot a test set, and can be told to fail -- which is the
// distinction the handler exists to make: an EMPTY snapshot is a success ("no
// focus" is an answer), and a `FocusError` is a channel that refused the
// question. A double that could only answer one of those could not tell the two
// apart, and they are the two things `getFocusInfo` says.
//
// It counts calls because focus is a READ: a handler that asked twice per
// command would double what the command costs on a machine where each ask is a
// subprocess.

import VoiceOverBridgeDomain

public final class FakeFocusInspector: FocusInspector {
	/// What `focusInfo()` answers. The default is the empty snapshot, which is
	/// what a real one gives when nothing is focused.
	public var snapshot = FocusSnapshot()

	/// When set, `focusInfo()` throws this instead of answering.
	public var failure: FocusError?

	public private(set) var reads = 0

	public init() {}

	public func focusInfo() throws -> FocusSnapshot {
		reads += 1
		if let failure { throw failure }
		return snapshot
	}
}
