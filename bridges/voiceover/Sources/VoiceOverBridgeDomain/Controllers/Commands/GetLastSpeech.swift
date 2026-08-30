// ROLE: controller -- `getLastSpeech`: the most recent utterance, with no params.
//
// BUILT BY: Registry. READS: the session's SpeechBuffer.
//
// AN EMPTY BUFFER IS AN EMPTY TEXT, NOT AN ERROR. A session that has not made
// the reader say anything yet asks a legitimate question, and the sentinel at
// index 0 is what answers it -- with an empty `emittedAt`, because nothing was
// emitted and reporting an instant would claim something happened.

import ScreenReaderWire

public final class GetLastSpeechHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let (utterance, index) = try context.speechBuffer().last()
		return LastSpeechResult(
			text: utterance.text,
			index: index,
			// No journal to position into; see GetSpeech.
			logPosition: 0,
			emittedAt: Wallclock.format(utterance.emittedAt)
		)
	}
}
