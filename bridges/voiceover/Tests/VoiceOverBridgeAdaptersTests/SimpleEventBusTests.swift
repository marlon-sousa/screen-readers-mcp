// Mirrors Sources/VoiceOverBridgeAdapters/SimpleEventBus.swift.

import Foundation
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("SimpleEventBus")
struct SimpleEventBusTests {
	private let listening = BridgeEvent.serverStatus(ServerStatus(state: .listening, endpoint: "e"))
	private let stopped = BridgeEvent.serverStatus(ServerStatus(state: .stopped, endpoint: nil))

	@Test("every subscriber sees every event, in order")
	func everySubscriberSeesEverything() {
		let bus = SimpleEventBus()
		var first: [BridgeEvent] = []
		var second: [BridgeEvent] = []
		_ = bus.subscribe { first.append($0) }
		_ = bus.subscribe { second.append($0) }
		bus.emit(listening)
		bus.emit(stopped)
		#expect(first == [listening, stopped])
		#expect(second == [listening, stopped])
	}

	@Test("unsubscribing stops delivery, and unsubscribing twice is harmless")
	func unsubscribe() {
		let bus = SimpleEventBus()
		var seen: [BridgeEvent] = []
		let token = bus.subscribe { seen.append($0) }
		bus.emit(listening)
		bus.unsubscribe(token)
		bus.unsubscribe(token)
		bus.emit(stopped)
		#expect(seen == [listening])
	}

	@Test("emitting with nobody listening is not an error")
	func noSubscribers() {
		SimpleEventBus().emit(listening)
	}

	@Test("a subscriber may leave from inside its own handler without deadlocking")
	func reentrantUnsubscribe() {
		// The reason handlers are called OUTSIDE the lock: a view that tears itself
		// down when it sees `stopped` would otherwise deadlock the accept thread,
		// and it would do it only on the path where the bridge is shutting down.
		let bus = SimpleEventBus()
		var token: SubscriptionToken?
		var seen = 0
		token = bus.subscribe { _ in
			seen += 1
			if let token { bus.unsubscribe(token) }
		}
		bus.emit(listening)
		bus.emit(stopped)
		#expect(seen == 1)
	}

	@Test("emitting from another thread while subscribing on this one is safe")
	func concurrentEmitAndSubscribe() {
		// Why the lock is not defensive habit: emit runs on the accept thread the
		// moment a session starts, while subscribe and unsubscribe run wherever a
		// view lives. Unguarded, this is a corrupted dictionary rather than a
		// wrong answer.
		let bus = SimpleEventBus()
		let group = DispatchGroup()
		DispatchQueue.global().async(group: group) {
			for _ in 0..<200 { bus.emit(self.listening) }
		}
		DispatchQueue.global().async(group: group) {
			for _ in 0..<200 { bus.unsubscribe(bus.subscribe { _ in }) }
		}
		#expect(group.wait(timeout: .now() + 5) == .success)
	}
}
