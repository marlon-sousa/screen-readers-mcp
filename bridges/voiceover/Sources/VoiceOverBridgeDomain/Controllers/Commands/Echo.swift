// ROLE: controller -- returns the request's payload unchanged.
//
// BUILT BY: Registry. Needs nothing from the SessionContext, and that is the
// point of it: its whole value is proving that the full wire stack -- encode,
// frame, decode, validate, dispatch, re-encode -- survives an arbitrary payload,
// which no fake and no reader-edge command can isolate.

import ScreenReaderWire

public final class EchoHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let params = try request.params(as: EchoParams.self)
		return EchoResult(payload: params.payload)
	}
}
