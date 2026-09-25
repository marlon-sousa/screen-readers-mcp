// ROLE: controller -- `getNextSpeechIndex`: the bookmark, with no params.
// BUILT BY: Registry. READS: the session's SpeechBuffer.

import ScreenReaderWire

public final class GetNextSpeechIndexHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		NextIndexResult(index: try context.speechBuffer().nextIndex())
	}
}
