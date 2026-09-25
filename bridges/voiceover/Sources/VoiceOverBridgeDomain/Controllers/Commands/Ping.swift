// ROLE: controller for `ping`, the liveness probe and the only handler that does not reset the
// command-inactivity watchdog.
//
// BUILT BY: Registry.
// `suppressing` is nil before the handshake, meaning "this bridge does not say", never false.

import ScreenReaderWire

public final class PingHandler: CommandHandler {
	public let resetsInactivity = false

	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		PingResult(suppressing: context.adapters?.silenceControl.isSuppressing)
	}
}
