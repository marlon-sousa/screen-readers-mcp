// ROLE: supporting construct, the one place that decides whether "the reader said nothing" is an
// answer or a symptom.
// USED BY: WaitForSpeech.
// Anything ever captured proves the provider is capturing, so the probe runs only while the buffer
// is empty.

public enum UnheardSpeech {
	/// Turn an unexplained silence into a named condition, or say nothing.
	/// Throws a `CommandError` naming each condition and its recovery; returns quietly when the reader
	/// edge is healthy.
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
