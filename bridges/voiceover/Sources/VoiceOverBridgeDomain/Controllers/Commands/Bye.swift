// ROLE: controller -- the client ends the session.
//
// BUILT BY: Registry. Uses the SessionContext's one lifecycle capability,
// `close(_:)`, to ask for teardown, and returns the ack.
//
// THE ACK IS WRITTEN BEFORE THE TEARDOWN HAPPENS, and that ordering is the
// Session's, not this handler's: teardown is cooperative and honoured at the
// loop's next wakeup, so the client always sees its goodbye acknowledged rather
// than losing the reply to a socket that closed first.

import ScreenReaderWire

public final class ByeHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		context.close(.clientBye)
		return AckResult()
	}
}
