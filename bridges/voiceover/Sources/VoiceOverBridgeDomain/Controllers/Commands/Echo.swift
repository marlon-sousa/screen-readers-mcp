// ROLE: controller -- returns the request's payload unchanged.
// BUILT BY: Registry.

import ScreenReaderWire

public final class EchoHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let params = try request.params(as: EchoParams.self)
		return EchoResult(payload: params.payload)
	}
}
