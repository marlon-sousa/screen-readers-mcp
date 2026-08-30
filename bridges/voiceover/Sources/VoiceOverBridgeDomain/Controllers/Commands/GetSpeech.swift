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
// THE MAPPING TO WIRE ENTRIES MOVED TO `Observation` AT 13.7, when a second
// command started assembling the same answer. `logPosition` is always 0 and
// that is the honest answer rather than a stub -- it is a coordinate into
// NVDA's log journal, and VoiceOver emits no diagnostic log of its own to
// position into (spec 0046, Part 2) -- and it is now stated in ONE place, so
// the day this reader grows a journal it cannot be half-corrected.

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
