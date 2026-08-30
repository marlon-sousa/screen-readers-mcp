// ROLE: controller -- the liveness probe, and the ONLY handler that does not
// reset the command-inactivity watchdog.
//
// BUILT BY: Registry. Holds nothing: a stateless singleton, like every handler
// except hello, because the per-session state lives in the SessionContext it is
// handed.
//
// WHY IT MUST NOT RESET INACTIVITY: the heartbeat asks "is the harness process
// alive?" and a ping answers it. Inactivity asks "is the agent still testing?"
// and a ping answers nothing -- a keepalive loop that reset it would keep a
// dead-in-the-water session open forever, which is the exact thing the second
// watchdog exists to end.
//
// `suppressing` IS ANSWERED SINCE 13.6, AND NIL IS STILL A THIRD ANSWER RATHER
// THAN A FALSE ONE. Before the handshake there is no silence control to ask, so
// the honest answer is "this bridge does not say" -- and this is the round trip
// the server's `status` tool makes, so a wrong `false` would be read as proof.
// After the handshake the marker file is the truth and it is read from the
// adapter that writes it.
//
// IT IS ALSO THE ONE CHANNEL AN AGENT HAS FOR NOTICING A LIFT. Nothing is pushed
// when the silence cap fires (protocol.md §6.1, rule 3): an agent that never
// looks carries on working correctly, and one that wants to know reads this.

import ScreenReaderWire

public final class PingHandler: CommandHandler {
	public let resetsInactivity = false

	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		PingResult(suppressing: context.adapters?.silenceControl.isSuppressing)
	}
}
