// ROLE: controller -- `waitForSpeech`: block until the reader says something.
// BUILT BY: Registry. READS: the session's SpeechBuffer.
// A miss is a result, not an error: the index is a fresh bookmark and `emittedAt` is empty.
// A miss on a session that has captured nothing throws a named condition instead; see UnheardSpeech.

import ScreenReaderWire

public final class WaitForSpeechHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let params = try request.params(as: WaitForSpeechParams.self)
		let outcome = try context.speechBuffer().waitFor(
			params.text, afterIndex: params.afterIndex, timeout: params.timeout
		)
		if !outcome.found {
			try UnheardSpeech.explain(context)
		}
		return WaitForSpeechResult(
			found: outcome.found,
			index: outcome.index,
			text: outcome.utterance.text,
			// VoiceOver has no log journal to position into; see Observation.
			logPosition: 0,
			emittedAt: outcome.found ? Wallclock.format(outcome.utterance.emittedAt) : ""
		)
	}
}
