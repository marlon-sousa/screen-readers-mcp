// ROLE: adapter -- IMPLEMENTS the EventBus domain port, in process.
//
// BUILT BY: Wiring, at singleton scope. EMITTED TO BY: BridgeServer.
// SUBSCRIBED TO BY: the control dialog (13.10).
//
// A LOCK GUARDS EVERY ACCESS, and it is not defensive habit: `emit` runs on the
// accept thread while `subscribe` and `unsubscribe` run on the main thread the
// moment a dialog exists. Handlers are then called OUTSIDE the lock, on the
// emitter's thread, so a subscriber that blocks cannot deadlock the server and a
// subscriber that touches AppKit is responsible for marshalling itself.
//
// A THROWING HANDLER IS SWALLOWED because a view that fails to refresh must not
// take down the connection edge that told it to.

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
