// ROLE: controller -- `waitForSpeech`: block until the reader says something.
//
// BUILT BY: Registry. READS: the session's SpeechBuffer, whose wait loop sleeps
// the injected Clock.
//
// IT BLOCKS THE SESSION THREAD, ON PURPOSE AND SAFELY. The request's own timeout
// is well below both watchdog windows, and dispatching this command already
// reset the inactivity mark, so a wait cannot trip a deadline it is itself the
// evidence against.
//
// A MISS IS A RESULT, NOT AN ERROR. `found == false` means the reader did not
// say it, which is frequently the assertion a test is making; an error frame
// would force every caller to catch in order to learn a fact. The index that
// comes back on a miss is a fresh bookmark, so the caller can carry on from
// there -- but `emittedAt` is EMPTY, deliberately, because nothing was emitted
// and reporting "now" would read as a match that happened (spec 0028).

import ScreenReaderWire

public final class WaitForSpeechHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let params = try request.params(as: WaitForSpeechParams.self)
		let outcome = try context.speechBuffer().waitFor(
			params.text, afterIndex: params.afterIndex, timeout: params.timeout
		)
		return WaitForSpeechResult(
			found: outcome.found,
			index: outcome.index,
			text: outcome.utterance.text,
			// No journal to position into; see GetSpeech.
			logPosition: 0,
			emittedAt: outcome.found ? Wallclock.format(outcome.utterance.emittedAt) : ""
		)
	}
}
