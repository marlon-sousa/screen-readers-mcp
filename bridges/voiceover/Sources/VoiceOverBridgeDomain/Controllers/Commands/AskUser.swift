// ROLE: controller for `askUser`: puts a question to the human and returns a ticket to
// collect the answer with.
// BUILT BY: Registry. DRIVES: the UserPrompter, Announcer and SilenceControl ports, and the
// session's silence cap.
// Returns at once: the session thread renews the silence lease, so waiting here for the human
// would unmute the machine.
// A silent session passes through while the window is open; `suspendedSilence` records that,
// so `waitForUserReply` restores only what this took.

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
			// The window is up and the ticket is real, so the command still succeeds.
			context.transcript.note("askUser: the question could not be spoken: \(describe(error))")
		}
		context.transcript.note("askUser: prompt presented (ticket \(ticket))")
		context.humanHeard()
		return AskUserResult(ticket: ticket)
	}

	private func describe(_ error: any Error) -> String {
		String(describing: error)
	}
}
