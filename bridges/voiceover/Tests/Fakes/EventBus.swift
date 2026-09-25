import Foundation
import VoiceOverBridgeDomain

public final class FakeEventBus: EventBus {
	private let lock = NSRecursiveLock()
	private var events: [BridgeEvent] = []
	private var handlers: [SubscriptionToken: (BridgeEvent) -> Void] = [:]
	private var nextToken = 0

	public init() {}

	/// Copied under the lock, because the emitter is the server thread and the reader is the test's.
	public var emitted: [BridgeEvent] {
		lock.lock()
		defer { lock.unlock() }
		return events
	}

	public var states: [ServerState] {
		emitted.map { event in
			switch event {
			case .serverStatus(let status): return status.state
			}
		}
	}

	public func subscribe(_ handler: @escaping (BridgeEvent) -> Void) -> SubscriptionToken {
		lock.lock()
		defer { lock.unlock() }
		nextToken += 1
		let token = "fake-\(nextToken)"
		handlers[token] = handler
		return token
	}

	public func unsubscribe(_ token: SubscriptionToken) {
		lock.lock()
		handlers.removeValue(forKey: token)
		lock.unlock()
	}

	public func emit(_ event: BridgeEvent) {
		lock.lock()
		events.append(event)
		let snapshot = Array(handlers.values)
		lock.unlock()
		for handler in snapshot {
			handler(event)
		}
	}
}
