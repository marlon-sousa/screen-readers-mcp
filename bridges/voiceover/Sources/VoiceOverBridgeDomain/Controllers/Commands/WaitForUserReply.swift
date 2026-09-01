// ROLE: controller -- `waitForUserReply`: poll for the human's answer to the
// ticket `askUser` handed back.
//
// BUILT BY: Registry. DRIVES: the UserPrompter port (the poll), the
// SilenceControl (putting back what `askUser` took) and the session's silence
// cap. READS: the outstanding UserPrompt entity, for the window's own deadline.
//
// A POLL, NOT AN AWAIT, and the whole argument is in UserPrompter's header: the
// thread this would block is the one that renews the silence lease, so parking
// it on a human's decision is the one thing 13.6's design exists to prevent.
// What blocks here instead is bounded by the request's own timeout, exactly as
// `waitForSpeech` is, and it sleeps the injected Clock so a test pays nothing.
//
// A MISS IS A RESULT, NOT AN ERROR, on `waitForSpeech`'s manners and for the
// same reason: "they have not answered yet" is a fact an agent branches on, and
// an error frame would make it catch in order to learn it. The window stays open
// across a miss, so the next poll continues the same wait.
//
// THREE WAYS THIS ENDS THE WINDOW, and only the first is an answer:
//
//  1. The human answered -- `answered: true`, with their text.
//  2. The human dismissed it, or the bridge took it away -- `answered: false`.
//  3. The window's own 300 s deadline passed with nothing -- `answered: false`.
//
// All three CLOSE the prompt: the window is taken away, and a silent session
// goes quiet again if this prompt is what un-muted it. A fourth outcome, the
// poll's own timeout, ends nothing.
//
// THE POLL IS CLAMPED, for the reason `maxPollTimeout` states: the inactivity
// watchdog is measured from DISPATCH and is not extended by a handler that
// blocks, so a poll allowed to run past it would answer the agent and have the
// session torn down under it one line later. Clamping in the bridge protects
// every client, not only the one whose tool schema is polite.

import Foundation
import ScreenReaderWire

/// How often the prompt is looked at while waiting.
///
/// Slower than the speech buffer's cadence on purpose: what is being waited for
/// is a human reading a question and typing, not a machine emitting an
/// utterance, and a tenth of a second is imperceptible against that while
/// costing a thirtieth of the wakeups.
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
			// The poll's own timeout, which ends THIS call and not the window.
			if now >= deadline {
				return WaitForUserReplyResult(answered: false)
			}
			context.clock.sleep(promptPollInterval)
		}
	}

	// -- closing the window ----------------------------------------------------

	/// Take the window away and put back what asking cost.
	///
	/// IT RESUPPRESSES ONLY WHAT THIS PROMPT LIFTED, and only while the session is
	/// still entitled to be silent -- but a cap that has already fired is NOT this
	/// command's business to undo. It calls `humanHeard`, and since 2026-09-01 the
	/// SESSION re-arms on the very next tick, audibly marked, on a fresh window
	/// (protocol.md §6.1, rule 4). Re-muting from here would take the machine away
	/// silently, in the one place where the person is standing at the keyboard
	/// having just answered a question.
	/// One rendering for every error these handlers report: `String(describing:)`
	/// asks a `CustomStringConvertible` for its `description` first, so a
	/// `CommandError` or an `AnnouncerError` reads as its own sentence. Spelled
	/// this way rather than as an `as?` cast, which the compiler warns is always
	/// true -- every `Error` satisfies that protocol.
	private func describe(_ error: any Error) -> String {
		String(describing: error)
	}

	private func close(_ context: SessionContext, _ prompt: UserPrompt, _ adapters: AdapterSet) {
		adapters.userPrompter.cancel(prompt.ticket)
		context.outstandingPrompt = nil
		// The human has just been at their machine, hearing it: a fresh window,
		// whether they answered or walked away.
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
