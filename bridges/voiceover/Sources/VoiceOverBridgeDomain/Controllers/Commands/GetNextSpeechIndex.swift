// ROLE: controller -- `getNextSpeechIndex`: the bookmark, with no params.
//
// BUILT BY: Registry. READS: the session's SpeechBuffer.
//
// IT IS THE INDEX THE NEXT UTTERANCE WILL GET, not the last one used. An agent
// marks its place BEFORE acting and then reads or waits from that mark, so
// speech that was already in flight when it acted can never be mistaken for the
// answer to its action. That ordering is the whole reason this command exists as
// its own round trip.

import ScreenReaderWire

public final class GetNextSpeechIndexHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		NextIndexResult(index: try context.speechBuffer().nextIndex())
	}
}
