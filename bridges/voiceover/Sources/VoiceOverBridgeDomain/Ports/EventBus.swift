// ROLE: port -- a publish/subscribe channel for what the connection edge is
// doing, so a view can reflect it without polling.
//
// IMPLEMENTED BY: SimpleEventBus (adapters); FakeEventBus (Tests/Fakes).
// EMITTED TO BY: BridgeServer, after every state transition.
// SUBSCRIBED TO BY: the launcher, which prints each transition, and by the
// control dialog when it lands. The port is here because BridgeServer is here,
// and a server that gained an observer later would have to grow one into a class
// that had already been written without one.
//
// THE EVENT TYPES LIVE IN THIS FILE, WITH THE PORT THAT CARRIES THEM, and that
// is a departure from the NVDA bridge worth stating. There, the payload is
// `Any` and the status type lives with BridgeServer; typed here, that would make
// the domain's port depend on an adapter. So the server's OBSERVABLE STATE is
// named here -- it is what the port carries -- while the accept loop that
// produces it stays in the adapters where its collaborators are.
//
// HANDLERS ARE CALLED ON THE PUBLISHER'S THREAD, which is the accept loop's.
// A subscriber that touches AppKit marshals to the main thread itself; that is
// the macOS rendering of the NVDA main-thread rule, and the control dialog is
// where it will bite.

/// What the connection edge is doing.
public enum ServerState: String, Equatable, Sendable {
	case stopped
	case listening
	case sessionActive
}

/// A snapshot of the connection edge. `endpoint` is the accepting address while
/// listening or active, and nil when stopped.
public struct ServerStatus: Equatable, Sendable {
	public let state: ServerState
	public let endpoint: String?

	public init(state: ServerState, endpoint: String?) {
		self.state = state
		self.endpoint = endpoint
	}
}

/// Something the bridge did that a view may want to reflect.
public enum BridgeEvent: Equatable, Sendable {
	case serverStatus(ServerStatus)
}

/// Handed back by `subscribe`, and the only thing needed to `unsubscribe`, so a
/// subscriber does not have to keep its own closure around to be able to leave.
public typealias SubscriptionToken = String

public protocol EventBus: AnyObject {
	func subscribe(_ handler: @escaping (BridgeEvent) -> Void) -> SubscriptionToken

	/// Remove the subscription. Safe to call twice, and safe with a token that
	/// was already removed.
	func unsubscribe(_ token: SubscriptionToken)

	func emit(_ event: BridgeEvent)
}
