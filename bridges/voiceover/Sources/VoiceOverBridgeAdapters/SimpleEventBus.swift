// ROLE: adapter implementing the EventBus port, in process.
// BUILT BY: Wiring, at singleton scope; BridgeServer emits to it.
// USED BY: the launcher, which prints each transition, and the control dialog.
// Handlers run outside the lock, on the emitter's thread, so a subscriber touching AppKit must marshal itself.

import Foundation
import VoiceOverBridgeDomain

public final class SimpleEventBus: EventBus {
	private let lock = NSLock()
	private var handlers: [SubscriptionToken: (BridgeEvent) -> Void] = [:]

	public init() {}

	public func subscribe(_ handler: @escaping (BridgeEvent) -> Void) -> SubscriptionToken {
		let token = UUID().uuidString
		lock.lock()
		handlers[token] = handler
		lock.unlock()
		return token
	}

	public func unsubscribe(_ token: SubscriptionToken) {
		lock.lock()
		handlers.removeValue(forKey: token)
		lock.unlock()
	}

	public func emit(_ event: BridgeEvent) {
		lock.lock()
		let snapshot = Array(handlers.values)
		lock.unlock()
		for handler in snapshot {
			handler(event)
		}
	}
}
