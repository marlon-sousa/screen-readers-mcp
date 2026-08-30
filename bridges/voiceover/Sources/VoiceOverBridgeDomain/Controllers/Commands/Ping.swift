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
// `suppressing` IS NIL HERE, AND NIL IS A THIRD ANSWER RATHER THAN A FALSE ONE.
// Nothing in this build can suppress speech, so nothing can honestly report on
// it; 13.6 brings the silence control that can, and this is the round trip the
// server's `status` tool makes, so a wrong `false` would be read as proof.

import ScreenReaderWire

public final class PingHandler: CommandHandler {
	public let resetsInactivity = false

	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		PingResult()
	}
}
