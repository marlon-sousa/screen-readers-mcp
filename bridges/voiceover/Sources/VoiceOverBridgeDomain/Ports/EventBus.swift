// ROLE: port -- a publish/subscribe channel for what the connection edge is doing.
// IMPLEMENTED BY: SimpleEventBus; FakeEventBus.
// USED BY: BridgeServer, which emits after every state transition, and the launcher, which subscribes.
// Handlers run on the publisher's thread, the accept loop's; a subscriber that touches AppKit must marshal to the main thread.

public enum ServerState: String, Equatable, Sendable {
	case stopped
	case listening
	case sessionActive
}

/// `endpoint` is nil when stopped.
public struct ServerStatus: Equatable, Sendable {
	public let state: ServerState
	public let endpoint: String?

	public init(state: ServerState, endpoint: String?) {
		self.state = state
		self.endpoint = endpoint
	}
}

public enum BridgeEvent: Equatable, Sendable {
	case serverStatus(ServerStatus)
}

public typealias SubscriptionToken = String

public protocol EventBus: AnyObject {
	func subscribe(_ handler: @escaping (BridgeEvent) -> Void) -> SubscriptionToken

	/// Safe to call twice, and with a token already removed.
	func unsubscribe(_ token: SubscriptionToken)

	func emit(_ event: BridgeEvent)
}
