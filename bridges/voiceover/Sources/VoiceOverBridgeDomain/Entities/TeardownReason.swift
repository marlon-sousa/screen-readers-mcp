// ROLE: entity -- every way a session can end.
//
// Pure, and domain-only: it never crosses the wire, so it is not in the wire
// binding. The raw value is the string the transcript's SESSION CLOSE line
// carries, which is the same vocabulary lane 1 writes, so a transcript from
// either bridge reads the same way.
//
// SET BY: the Session on every exit path, and by whoever asks it to stop -- the
// `bye` handler through the context's one lifecycle capability, and BridgeServer
// when the machine is shutting the bridge down.
public enum TeardownReason: String, Equatable, Sendable {
	/// The client said goodbye. The orderly path.
	case clientBye = "client-bye"

	/// The peer went away. Normal too: a client that exits is a client that has
	/// finished.
	case channelClosed = "channel-closed"

	/// Nothing at all arrived for the heartbeat window: the harness PROCESS is
	/// presumed gone.
	case heartbeatTimeout = "heartbeat-timeout"

	/// Pings kept arriving but no real command did: the AGENT has stopped testing.
	case inactivityTimeout = "inactivity-timeout"

	/// The handshake did not complete -- a bad version, an unreadable first line,
	/// or any command before `hello`.
	case handshakeFailed = "handshake-failed"

	/// Somebody outside the session asked it to stop.
	case external
}
