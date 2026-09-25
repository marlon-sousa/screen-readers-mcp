// ROLE: port -- the session's request/response seam with the outside world.
// IMPLEMENTED BY: JsonLinesChannel, over the Transport seam; FakeChannel.
// USED BY: the Session controller, its only I/O collaborator.
// A read returns a raw object, so the Session can still answer with the line's id when it fails to decode as a request.

import ScreenReaderWire

public struct ChannelClosed: Error {
	public init() {}
}

/// `timedOut` is the poll window elapsing, not a failure.
public enum ChannelRead: Equatable {
	case message([String: JSONValue])
	case timedOut
}

public protocol MessageChannel: AnyObject {
	/// Throws `ChannelClosed` when the peer has gone, and `ValidationError` for an unreadable line, which the Session survives.
	func read() throws -> ChannelRead

	func write(_ response: Response) throws

	func close()
}
