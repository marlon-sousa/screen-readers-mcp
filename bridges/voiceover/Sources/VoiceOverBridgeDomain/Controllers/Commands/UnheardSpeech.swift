// ROLE: supporting construct in the controllers layer -- the ONE place that
// decides whether "the reader said nothing" is an answer or a symptom.
//
// USED BY: WaitForSpeech, and by nothing else. The three neighbours are
// deliberate exclusions rather than omissions:
//
//  * `getSpeech` and `getLastSpeech` REPORT a buffer rather than wait on one, and
//    putting a machine-state probe on the cheapest reads in the protocol would
//    charge every poll for a question nobody asked.
//  * `waitForSpeechToFinish` is a legitimate FIRST call -- an agent settling a
//    session before it does anything expects a quiet buffer and gets one, so
//    treating "quiet" as a symptom there would fail on the healthiest possible
//    session.
//
// `waitForSpeech` is different in kind: the agent has said, in the request, that
// it expects the reader to have spoken. Coming back empty from THAT, with
// nothing ever captured, is a claim about a reader we may never have been
// listening to.
//
// WHY IT EXISTS. A miss is normally a RESULT, not an error: "the reader did not
// say it" is frequently the assertion a test is making, and an error frame would
// force every caller to catch in order to learn a fact. That reasoning holds
// exactly as long as the bridge is in a position to have heard. When it is not
// -- the voice is not selected, the provider is not registered, the reader never
// offered the voice -- the same empty answer means something completely
// different, and spec 0041's sharpest requirement is that a bridge on this route
// must not let those two look alike:
//
//   "returning an empty read-back is what a naive implementation does, and it is
//    wrong."
//
// THE PROBE IS PAID FOR AT MOST ONCE PER SESSION-WITH-NOTHING-CAPTURED, which is
// what makes asking affordable. If anything has ever been captured, the provider
// is demonstrably capturing (spec 0047, finding 18: utterances arriving is the
// only reliable signal, never audio), so a miss is a genuine miss and no
// question is asked at all. The check therefore costs subprocesses only in the
// case where the agent is about to be misled -- and it costs them after a
// timeout that has already spent seconds.

public enum UnheardSpeech {
	/// Turn an unexplained silence into a named condition, or say nothing.
	///
	/// Called only after a wait for WORDS came back empty. Throws a `CommandError` naming
	/// every condition that could explain it, each with its own recovery, and
	/// returns quietly when the reader edge is healthy -- in which case the miss
	/// is the honest answer the caller already has.
	public static func explain(_ context: SessionContext) throws {
		guard let lifecycle = context.adapters?.providerLifecycle,
			let buffer = context.speech,
			buffer.isEmpty
		else { return }
		let state = lifecycle.state()
		let conditions = state.unheardConditions
		guard !conditions.isEmpty else { return }
		let named = conditions.map(\.described).joined(separator: " ")
		context.transcript.note("unheard speech: \(state.diagnosis). \(named)")
		throw CommandError(
			"nothing has been captured in this session, and the reader edge cannot account for it: "
				+ "\(state.diagnosis). \(named)")
	}
}
