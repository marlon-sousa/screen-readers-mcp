// ROLE: entity -- which of the two transports protocol.md §1 allows this bridge
// to accept connections on.
//
// Pure, and read by BridgeConfig (the persisted preference), by Wiring (which
// listener to build) and by the launcher; the control dialog's combo box will
// read the same value. It is
// NOT on the wire: the server and the bridge agree on a transport before `hello`
// and never mention it again, which is why nothing in ScreenReaderWire knows
// this type exists.
//
// A LAYOUT AMENDMENT, RECORDED HERE BECAUSE IT IS A RENAME AND NOT A NEW IDEA.
// Spec 0046's 13.4 table describes `ConnectionMode.swift` as "silent / live, and
// the defaults each implies", which is the CAPTURE mode -- and that already
// exists, as `CaptureMode` in the wire binding, where it belongs because it does
// cross the wire. What 13.4 actually needs under this name is the transport
// choice, exactly as lane 1 has it in `domain/entities/connection_mode.py`. The
// name is kept and the meaning is lane 1's.
//
// REMOTE TCP IS NOT A CASE. Lane 1 defines one and greys it out; this bridge
// does not define it at all, because remote TCP is remote keystroke injection
// and it is deferred behind its own security entry. An enum case nobody may
// select is an invitation, and there is no dialog here yet to grey it out in.
public enum ConnectionMode: String, CaseIterable, Equatable, Sendable {
	/// The default. A bare name that resolves to a Unix domain socket here and to
	/// a named pipe on Windows -- one shipped default that works on every host
	/// (spec 0044).
	case localEndpoint

	/// Loopback TCP, for the cases where a socket file is awkward: a client that
	/// cannot address one, or a diagnosis that wants `nc`.
	case loopbackTcp

	/// What a bridge listens on when nobody has chosen.
	public static let `default` = ConnectionMode.localEndpoint
}

/// The port loopback TCP uses when nobody has chosen (protocol.md §1).
public let defaultLoopbackPort = 8765

/// The endpoint name this bridge ships with.
///
/// `<reader>McpBridge`, where `<reader>` is the same value `hello` sends as
/// `reader.name` -- protocol.md §1's naming convention, which exists so a server
/// can ship one default entry per reader that works on every host. It confers no
/// trust: `hello` remains the only authority on which reader actually answered.
public let defaultEndpointName = "voiceoverMcpBridge"
