// A hand-written stateful fake for the PermissionBroker port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/PermissionBroker.swift.
//
// IT EXISTS TO MAKE ONE MISTAKE UNAVAILABLE, and this one cannot be undone. The
// real broker's `request` raises a system consent dialog and leaves the process
// on a list that STAYS granted afterwards -- so a test that reached it would
// change the developer's machine permanently, in exactly the way the entry it
// belongs to exists to keep deliberate. No test may touch the real grant.
//
// IT COUNTS REQUESTS SEPARATELY FROM STATUS READS, and that is the point of the
// file rather than bookkeeping. The whole claim 13.8 makes is about WHEN the
// request happens: never at construction, never at the handshake, never for a
// gesture -- only on a `typeText`. A double that only answered "granted" could
// not tell a bridge that asks once from one that asks at startup, which is the
// difference the entry is about.

import VoiceOverBridgeDomain

public final class FakePermissionBroker: PermissionBroker {
	/// What `status` answers. Mutable, so a test can make a request SUCCEED by
	/// flipping it inside `onRequest` -- which is what a human granting the
	/// permission looks like from here.
	public var state: PermissionState

	public private(set) var statusReads: [Permission] = []
	public private(set) var requests: [Permission] = []

	/// Called when a request is made, before the answer is read. The hook is how
	/// a test says "and the human granted it", without the fake having to guess
	/// which tests want that.
	public var onRequest: (() -> Void)?

	public init(state: PermissionState = .granted) {
		self.state = state
	}

	public func status(of permission: Permission) -> PermissionState {
		statusReads.append(permission)
		return state
	}

	public func request(_ permission: Permission) -> PermissionState {
		requests.append(permission)
		onRequest?()
		return state
	}
}
