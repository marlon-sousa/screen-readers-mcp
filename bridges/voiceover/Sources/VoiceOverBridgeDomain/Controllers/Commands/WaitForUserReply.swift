// ROLE: controller for `waitForUserReply`: polls for the human's answer to an `askUser` ticket.
// BUILT BY: Registry. DRIVES: the UserPrompter and SilenceControl ports and the silence cap.
// READS: the outstanding UserPrompt, for the window's own deadline.
// A miss leaves the window open; an answer, a dismissal or the window's own deadline closes it.
import Foundation
import ScreenReaderWire

/// How often the prompt is looked at while waiting.
public let promptPollInterval: Double = 0.1

public final class WaitForUserReplyHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let params = try request.params(as: WaitForUserReplyParams.self)
		guard let adapters = context.adapters else {
			throw CommandError("`waitForUserReply` was called before `hello` built the reader edge")
		}
		guard let prompt = context.outstandingPrompt, prompt.ticket == params.ticket else {
			throw CommandError(
				"no outstanding prompt with ticket '\(params.ticket)'; it may already have been "
					+ "answered, or its window may have expired")
		}

		let timeout = min(params.timeout, maxPollTimeout)
		if timeout < params.timeout {
			context.transcript.note(
				"waitForUserReply: poll timeout \(params.timeout) clamped to \(maxPollTimeout) "
					+ "(a blocking handler does not extend the inactivity window); poll again to keep "
					+ "waiting")
		}

		let deadline = context.clock.monotonic() + max(0, timeout)
		while true {
			if let outcome = adapters.userPrompter.reply(for: prompt.ticket) {
				close(context, prompt, adapters)
				switch outcome {
				case .answered(let text):
					context.transcript.note("askUser: prompt \(prompt.ticket) answered")
					return WaitForUserReplyResult(answered: true, text: text)
				case .dismissed:
					context.transcript.note("askUser: prompt \(prompt.ticket) dismissed unanswered")
					return WaitForUserReplyResult(answered: false)
				}
			}
			let now = context.clock.monotonic()
			if prompt.isExpired(now) {
				close(context, prompt, adapters)
				context.transcript.note("askUser: prompt \(prompt.ticket) expired before an answer")
				return WaitForUserReplyResult(answered: false)
			}
			// The poll's own timeout, which ends this call and not the window.
			if now >= deadline {
				return WaitForUserReplyResult(answered: false)
			}
			context.clock.sleep(promptPollInterval)
		}
	}

	private func describe(_ error: any Error) -> String {
		String(describing: error)
	}

	private func close(_ context: SessionContext, _ prompt: UserPrompt, _ adapters: AdapterSet) {
		adapters.userPrompter.cancel(prompt.ticket)
		context.outstandingPrompt = nil
		// The human has just been at their machine: a fresh window. Resuppress only what this prompt
		// lifted, never after the cap has fired; the session re-arms audibly on its own.
		context.humanHeard()
		guard prompt.suspendedSilence, context.silenceCap?.lifted != true else { return }
		do {
			try adapters.silenceControl.suppress()
			context.transcript.note("askUser: silence resumed now the prompt is closed")
		} catch {
			context.transcript.note(
				"askUser: the reader could not be silenced again after the prompt: \(describe(error))")
		}
	}
}
