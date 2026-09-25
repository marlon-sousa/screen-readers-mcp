// ROLE: entity -- every way a session can end.
// The raw value is the string the transcript's session close line carries.
// USED BY: the Session on every exit path, the `bye` handler and BridgeServer.
public enum TeardownReason: String, Equatable, Sendable {
	case clientBye = "client-bye"

	case channelClosed = "channel-closed"

	case heartbeatTimeout = "heartbeat-timeout"

	case inactivityTimeout = "inactivity-timeout"

	case handshakeFailed = "handshake-failed"

	case external
}
