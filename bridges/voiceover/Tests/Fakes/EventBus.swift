// A hand-written stateful fake for the EventBus port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/EventBus.swift.
//
// It records what was emitted, in order, which is the only thing BridgeServer's
// test needs from it: the SEQUENCE of states is the assertion -- listening,
// session active, listening again -- and a bus that merely held the latest one
// could not tell that story.

import Foundation
import VoiceOverBridgeDomain

public final class FakeEventBus: EventBus {
	private let lock = NSRecursiveLock()
	private var events: [BridgeEvent] = []
	private var handlers: [SubscriptionToken: (BridgeEvent) -> Void] = [:]
	private var nextToken = 0

	public init() {}

	/// Everything emitted so far. Copied under the lock, because the emitter is
	/// the server thread and the reader is the test's.
	public var emitted: [BridgeEvent] {
		lock.lock()
		defer { lock.unlock() }
		return events
	}

	/// The server states seen, in order -- the shape most assertions want.
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
