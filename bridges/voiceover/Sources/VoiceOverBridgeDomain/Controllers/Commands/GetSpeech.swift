// ROLE: controller -- `getSpeech`: everything the reader said since a bookmark.
//
// BUILT BY: Registry. HOLDS NOTHING -- a stateless singleton, like every handler
// but hello, because the per-session state is the SessionContext it is handed.
// READS: the session's SpeechBuffer, and nothing else.
//
// THE RANGE IS THE ANSWER, NOT THE ENTRIES. `fromIndex`/`toIndex` span the whole
// half-open window that was read, while the entries are only those with words in
// them, so a caller resumes from `toIndex` and never re-reads or skips. That is
// why each entry carries its own index rather than being counted from the start
// of the list.
//
// `logPosition` IS ALWAYS 0 HERE, and that is the honest answer rather than a
// stub: it is a coordinate into NVDA's log journal, and VoiceOver emits no
// diagnostic log of its own to position into (spec 0046, Part 2). The field
// stays in the shape because the shape is the contract's.

import ScreenReaderWire

public final class GetSpeechHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let params = try request.params(as: GetSpeechParams.self)
		let read = try context.speechBuffer().entriesSince(params.sinceIndex)
		return SpeechResult(
			entries: read.entries.map {
				SpeechEntry(
					text: $0.utterance.text,
					index: $0.index,
					logPosition: 0,
					emittedAt: Wallclock.format($0.utterance.emittedAt)
				)
			},
			fromIndex: read.fromIndex,
			toIndex: read.toIndex
		)
	}
}
