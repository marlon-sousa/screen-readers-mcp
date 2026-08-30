// ROLE: port -- the session's request/response seam with the outside world, and
// the two signalling types that are part of its read contract.
//
// IMPLEMENTED BY: JsonLinesChannel (adapters) over the Transport seam;
// FakeChannel (Tests/Fakes) over a scripted script of reads.
// USED BY: the Session controller -- its only I/O collaborator.
//
// THE DOMAIN NEVER SEES BYTES, SOCKETS OR JSON FRAMING. It reads a message,
// writes one, and closes. "Pure Swift" is not the test for whether code belongs
// in the domain: newline framing is pure and is still an adapter.
//
// A READ RETURNS A RAW OBJECT, NOT A Request, AND THAT IS DELIBERATE. A line
// that is valid JSON but not a valid request must still be answered with the id
// it carried, so the Session -- not the channel -- decodes it and can reach for
// `id` when the decode fails. The channel's job ends at "this line was a JSON
// object".

import ScreenReaderWire

/// The peer is gone. Its own type, in the file of the port that raises it, so
/// the Session can tell it apart from "quiet" and from "unreadable".
public struct ChannelClosed: Error {
	public init() {}
}

/// What one read produced.
///
/// `timedOut` is not a failure: it is the poll window elapsing, which is what
/// lets the Session periodically regain control and check its deadlines while
/// an agent is simply thinking. An enum rather than an optional because
/// "no message yet" and "a message that decoded to null" are different answers.
public enum ChannelRead: Equatable {
	case message([String: JSONValue])
	case timedOut
}

public protocol MessageChannel: AnyObject {
	/// The next message, or `.timedOut` when none arrived within the poll window.
	///
	/// Throws `ChannelClosed` when the peer has gone away, and a
	/// `ValidationError` when a line is unreadable -- which the Session reports
	/// and survives rather than dying on garbage bytes.
	func read() throws -> ChannelRead

	/// Send one reply frame.
	func write(_ response: Response) throws

	func close()
}
