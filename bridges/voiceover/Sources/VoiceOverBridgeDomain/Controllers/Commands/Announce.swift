// ROLE: controller -- `announce`: say something to the HUMAN at the reader.
//
// BUILT BY: Registry. DRIVES: the Announcer port, and the session's silence cap.
//
// THE FIRST OF THE THREE COMMANDS `interact` ANNOUNCES, and the one the other
// two are built on: `pressGesture` and `typeText` reach the same port through
// `HumanWarning`, and `askUser` speaks its question through it.
//
// IT IS AUDIBLE IN A SILENT SESSION, WHICH IS ITS WHOLE PURPOSE (protocol.md
// §5). On this platform the suppression is rendered inside the capture voice, so
// the Announcer speaks with the bridge's OWN synthesizer, outside VoiceOver
// entirely -- a cleaner bypass than NVDA's, where the same claim rests on the
// interception being a filter in front of a synth that is still loaded. See the
// port's header.
//
// `mutatesReader` IS FALSE, AND THAT IS A DECISION RATHER THAN A DEFAULT. It
// changes what the human HEARS and nothing about the machine under test: no
// keystroke, no focus change, no reader state. An observe-only session (spec
// 0017) is exactly the session that should be able to narrate what it is
// watching, so refusing it there would be the wrong way round. `askUser` sets
// the flag, because a question demands something of the person.
//
// THE BRIDGE ACKNOWLEDGES THAT IT SPOKE, NEVER THAT ANYONE LISTENED, which is
// why the result is the generic ack and why a failure to speak is an error frame
// rather than `ok: false`: the agent asked for something to happen to a human's
// ears, and "it did not" is a failed command.

import Foundation
import ScreenReaderWire

public final class AnnounceHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let params = try request.params(as: AnnounceParams.self)
		let words = params.text.trimmingCharacters(in: .whitespacesAndNewlines)
		// Whitespace is not an announcement. Acknowledged rather than refused: an
		// agent that computed an empty hint asked for nothing to be said, and
		// nothing was, which is a success and not a fault.
		guard !words.isEmpty else { return AckResult() }

		guard let adapters = context.adapters else {
			throw CommandError("`announce` was called before `hello` built the reader edge")
		}
		do {
			try adapters.announcer.announce(words)
		} catch {
			throw CommandError("nothing could be said to the human at the reader: \(describe(error))")
		}
		// AFTER THE WORDS WERE SPOKEN, not before, and the two live together for
		// the reason spec 0032 gives: the silence clock records when the human was
		// actually told, not when this bridge decided to tell them.
		context.transcript.announced(words)
		context.humanHeard()
		return AckResult()
	}

	/// One rendering for every error these handlers report: `String(describing:)`
	/// asks a `CustomStringConvertible` for its `description` first, so a
	/// `CommandError` or an `AnnouncerError` reads as its own sentence. Spelled
	/// this way rather than as an `as?` cast, which the compiler warns is always
	/// true -- every `Error` satisfies that protocol.
	private func describe(_ error: any Error) -> String {
		String(describing: error)
	}
}
