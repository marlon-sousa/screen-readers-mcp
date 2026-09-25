// ROLE: supporting construct, what a mutating command does with its `announce` field.
// USED BY: PressGesture and TypeText. DRIVES: the Announcer port.
// Spoken before the machine moves: a failure to speak throws, so nothing unannounced goes out.

public enum HumanWarning {
	/// Call before anything else in a mutating handler: before validation, the grant request or any event.
	public static func honour(_ context: SessionContext, _ announce: String) throws {
		let words = announce.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !words.isEmpty else { return }
		guard let adapters = context.adapters else {
			throw CommandError("a warning was announced before `hello` built the reader edge")
		}
		do {
			try adapters.announcer.announce(words)
		} catch {
			let reason = describe(error)
			throw CommandError(
				"the human at the reader could not be warned, so nothing was done to their machine: "
					+ "\(reason). Send the same call with `announce` empty to proceed without warning them")
		}
		// Recorded only once the words were spoken: the silence clock marks when the human was told.
		context.transcript.announced(words)
		context.humanHeard()
	}

	private static func describe(_ error: any Error) -> String {
		String(describing: error)
	}
}
