// ROLE: controller -- `askUser`: put a question in front of the human and hand
// the agent a ticket to collect the answer with.
//
// BUILT BY: Registry. DRIVES: the UserPrompter port (the window), the Announcer
// (the question, said out loud), the SilenceControl (the reader gets its voice
// back while the window is open) and the session's silence cap.
//
// IT RETURNS IMMEDIATELY, AND THAT IS THE CONTRACT RATHER THAN AN OPTIMISATION.
// protocol.md §5 makes asking and collecting TWO commands, so the answer is
// polled by `waitForUserReply`. A handler that waited here would hold the
// session thread on a human's decision -- and on this bridge that thread also
// RENEWS THE SILENCE LEASE, so the machine would un-mute itself while somebody
// read the question. See UserPrompter's header for the design that avoids it.
//
// ONE OUTSTANDING PROMPT AT A TIME. A second `askUser` is refused rather than
// queued: two windows would leave the human unable to tell which ticket they
// were answering, and the agent unable to tell which one it was polling.
//
// THE QUESTION IS BOTH SHOWN AND SPOKEN, and neither half is redundant. The
// window is what a sighted human sees and what a reader can be navigated to; the
// spoken copy is what reaches somebody whose reader this session has muted,
// through the same channel `announce` uses -- and protocol.md §6.1 counts an
// `askUser` among the sounds that get past the suppression precisely because of
// it.
//
// AND IT LIFTS THE SUPPRESSION WHILE IT ASKS. Asking a question of somebody
// whose screen reader this session has silenced is asking them to answer a
// dialog they cannot hear: they have to be able to read the field, hear what
// they type, and find the button. So a silent session passes through for as long
// as the window is open (protocol.md §5: `suppressing` is false then), and
// `waitForUserReply` puts back exactly what this took -- recorded on the prompt
// rather than re-derived, because a LIVE session took nothing.
//
// `mutatesReader` IS TRUE, unlike `announce`'s: a question demands something of
// the person at the machine and changes what their reader is doing, so an
// observe-only session (spec 0017) does not get to interrupt them.

import Foundation
import ScreenReaderWire

public final class AskUserHandler: CommandHandler {
	public let mutatesReader = true

	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let params = try request.params(as: AskUserParams.self)
		let question = params.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !question.isEmpty else {
			throw CommandError("`askUser` needs a prompt: an empty question cannot be answered")
		}
		guard let adapters = context.adapters else {
			throw CommandError("`askUser` was called before `hello` built the reader edge")
		}
		guard context.outstandingPrompt == nil else {
			throw CommandError(
				"a prompt is already outstanding on this session; collect it with `waitForUserReply` "
					+ "or let its window expire before asking another")
		}

		let ticket: PromptId
		do {
			ticket = try adapters.userPrompter.present(question)
		} catch {
			throw CommandError("the question could not be put to the human: \(describe(error))")
		}
		let prompt = UserPrompt(ticket: ticket, prompt: question, now: context.clock.monotonic())

		// THE READER COMES BACK BEFORE THE QUESTION IS SPOKEN, so the human can
		// hear their own machine while they answer. A failure here is NOTED AND
		// SURVIVED rather than fatal: the spoken copy below still reaches them, so
		// a question they can hear but not navigate is worth more than no question.
		if context.mode == .silent, adapters.silenceControl.isSuppressing {
			do {
				try adapters.silenceControl.passThrough()
				prompt.suspendedSilence = true
				context.transcript.note("askUser: silence suspended while the prompt is open")
			} catch {
				context.transcript.note(
					"askUser: the reader could not be un-muted for the prompt: \(describe(error))")
			}
		}
		context.outstandingPrompt = prompt

		do {
			try adapters.announcer.announce(question)
		} catch {
			// The window is up and the ticket is real, so the command SUCCEEDED --
			// the human can still see and answer it. What failed is the copy meant
			// for somebody who cannot see it, and that belongs in the record.
			context.transcript.note("askUser: the question could not be spoken: \(describe(error))")
		}
		context.transcript.note("askUser: prompt presented (ticket \(ticket))")
		context.humanHeard()
		return AskUserResult(ticket: ticket)
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
