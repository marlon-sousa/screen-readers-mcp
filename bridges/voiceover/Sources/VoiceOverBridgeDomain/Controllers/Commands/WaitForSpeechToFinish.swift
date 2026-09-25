// ROLE: controller -- `waitForSpeechToFinish`: block until the feed goes quiet.
// BUILT BY: Registry. READS: the session's SpeechBuffer, which owns the heuristic.
// Finished means the buffer stopped growing, not that audio ended: the capture voice receives an
// utterance before any audio exists.

import ScreenReaderWire

public final class WaitForSpeechToFinishHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let params = try request.params(as: WaitToFinishParams.self)
		return WaitToFinishResult(finished: try context.speechBuffer().waitToFinish(timeout: params.timeout))
	}
}
