// Hand-written stateful fake for the PermissionBroker port.
// The real broker raises a consent dialog whose grant persists on the machine, so no test may reach it.

import VoiceOverBridgeDomain

public final class FakePermissionBroker: PermissionBroker {
	public var state: PermissionState

	public private(set) var statusReads: [Permission] = []
	public private(set) var requests: [Permission] = []

	public var onRequest: (() -> Void)?

	public var states: [Permission: PermissionState] = [:]

	public init(state: PermissionState = .granted) {
		self.state = state
	}

	public func status(of permission: Permission) -> PermissionState {
		statusReads.append(permission)
		return states[permission] ?? state
	}

	public func request(_ permission: Permission) -> PermissionState {
		requests.append(permission)
		onRequest?()
		return state
	}
}
