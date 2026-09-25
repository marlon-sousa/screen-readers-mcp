// ROLE: controller -- `getSpeech`: everything the reader said since a bookmark.
// BUILT BY: Registry.
// READS: the session's SpeechBuffer, and nothing else.
// `fromIndex` and `toIndex` span the whole window read, while entries hold only utterances with
// words, so a caller resumes from `toIndex`.

import ScreenReaderWire

public final class GetSpeechHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let params = try request.params(as: GetSpeechParams.self)
		let read = try context.speechBuffer().entriesSince(params.sinceIndex)
		return SpeechResult(
			entries: Observation.speechEntries(read.entries),
			fromIndex: read.fromIndex,
			toIndex: read.toIndex
		)
	}
}
