// ROLE: controller -- `waitForSpeechToFinish`: block until the feed goes quiet.
//
// BUILT BY: Registry. READS: the session's SpeechBuffer, which owns the
// heuristic and the constant behind it.
//
// IT WAITS FOR THE BUFFER TO STOP GROWING, NOT FOR THE MACHINE TO FALL SILENT,
// and the difference is not pedantry on this route: the capture voice is handed
// an utterance BEFORE any audio exists, so speech can be "finished" here while
// the human is still hearing it -- and in silent mode (13.6) there is no audio
// to finish at all. protocol.md §7.1 states the same gap in its NVDA form.
//
// `finished == false` IS AN ANSWER, like waitForSpeech's miss: the reader was
// still producing speech when the timeout ran out.

import ScreenReaderWire

public final class WaitForSpeechToFinishHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let params = try request.params(as: WaitToFinishParams.self)
		return WaitToFinishResult(finished: try context.speechBuffer().waitToFinish(timeout: params.timeout))
	}
}
