// ROLE: supporting construct in the controllers layer -- what a mutating command
// does with its `announce` field.
//
// USED BY: PressGesture (13.7) and TypeText (13.8). DRIVES: the Announcer port,
// through the session's adapter set. No state and no IO of its own, so it is a
// function on an enum rather than a class: there is nothing to hold.
//
// IT EXISTS BECAUSE TWO COMMANDS MAKE THE SAME PROMISE ABOUT A HUMAN'S EARS, and
// the rule it enforces is not a formatting one: the two commands MUST NOT differ
// here, and written out twice they would, quietly, the first time one of them
// was reworded. A shared function makes them differ only by being edited on
// purpose.
//
// ============================================================================
// IT USED TO REFUSE A SILENT SESSION'S WARNING, AND 13.10 DELETED THAT REFUSAL
// IN THE COMMIT THAT MADE THE PROMISE KEEPABLE.
// ============================================================================
//
// Exactly as 13.6 deleted `VoiceOverAdapterFactory`'s refusal of a silent
// session, and for the same reason: this bridge does not half-keep a promise
// about somebody's ears. Until this entry there was no channel to the human at
// all, so `announce` in a silent session -- the one place it is the ONLY warning
// they would get -- was refused rather than dropped, and in a live session it
// was merely noted. Both of those are gone. The Announcer speaks with the
// bridge's own synthesizer, OUTSIDE VOICEOVER ENTIRELY, so the warning is
// audible in either mode and the asymmetry has nothing left to stand on.
//
// AND IT IS SPOKEN BEFORE THE MACHINE MOVES. If this session cannot tell the
// human what is about to happen to their machine, nothing happens to it: a
// failure to speak throws, and the caller's next line is the keystroke that
// would have gone out unannounced.

public enum HumanWarning {
	/// Warn the human about what is about to happen to their machine.
	///
	/// CALLED BEFORE ANYTHING ELSE IN A MUTATING HANDLER -- before the params are
	/// validated any further, before the Accessibility grant is asked for, and
	/// before a single event goes out.
	///
	/// Whitespace is not an announcement, so it is treated as absence: the field
	/// is optional on the wire and an agent that computed an empty hint asked for
	/// no warning, which is not the same as one that could not be given.
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
		// Recorded and counted only once the words were actually spoken (spec
		// 0032): the silence clock says when the human was told, not when this
		// bridge decided to tell them.
		context.transcript.announced(words)
		context.humanHeard()
	}

	/// One rendering for every error this reports: `String(describing:)`
	/// asks a `CustomStringConvertible` for its `description` first, so a
	/// `CommandError` or an `AnnouncerError` reads as its own sentence. Spelled
	/// this way rather than as an `as?` cast, which the compiler warns is always
	/// true -- every `Error` satisfies that protocol.
	private static func describe(_ error: any Error) -> String {
		String(describing: error)
	}
}
