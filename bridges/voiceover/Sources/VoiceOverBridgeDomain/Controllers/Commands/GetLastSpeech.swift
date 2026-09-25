// ROLE: controller -- `getLastSpeech`: the most recent utterance, with no params.
// BUILT BY: Registry. READS: the session's SpeechBuffer.
// An empty buffer answers with the index-0 sentinel, empty text and empty `emittedAt`, not an error.

import ScreenReaderWire

public final class GetLastSpeechHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let (utterance, index) = try context.speechBuffer().last()
		return LastSpeechResult(
			text: utterance.text,
			index: index,
			// VoiceOver has no log journal to position into; see Observation.
			logPosition: 0,
			emittedAt: Wallclock.format(utterance.emittedAt)
		)
	}
}
