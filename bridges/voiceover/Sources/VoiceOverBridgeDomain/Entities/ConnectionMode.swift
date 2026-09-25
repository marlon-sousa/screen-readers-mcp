// ROLE: entity, which of the two transports this bridge accepts connections on.
// USED BY: BridgeConfig, Wiring and the launcher; it never crosses the wire.

public enum ConnectionMode: String, CaseIterable, Equatable, Sendable {
	/// The default: a bare name resolving to a Unix domain socket here and a named pipe on Windows.
	case localEndpoint

	case loopbackTcp

	public static let `default` = ConnectionMode.localEndpoint
}

/// The port loopback TCP uses when nobody has chosen.
public let defaultLoopbackPort = 8765

/// `<reader>McpBridge`, named after `reader.name`; it confers no trust, since only `hello` says
/// which reader answered.
public let defaultEndpointName = "voiceoverMcpBridge"
