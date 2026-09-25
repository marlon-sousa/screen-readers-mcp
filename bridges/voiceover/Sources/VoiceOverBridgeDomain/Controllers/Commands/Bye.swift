// ROLE: controller -- the client ends the session.
// BUILT BY: Registry.

import ScreenReaderWire

public final class ByeHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		context.close(.clientBye)
		return AckResult()
	}
}
