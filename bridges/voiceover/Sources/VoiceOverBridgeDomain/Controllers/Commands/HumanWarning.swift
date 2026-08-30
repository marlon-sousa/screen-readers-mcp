// ROLE: supporting construct in the controllers layer -- what a mutating command
// does with its `announce`, in the one build that has no channel to say it on.
//
// USED BY: PressGesture (13.7) and TypeText (13.8). No state and no IO, so it is
// a function on an enum rather than a class: there is nothing to hold.
//
// IT EXISTS BECAUSE TWO COMMANDS MAKE THE SAME PROMISE ABOUT A HUMAN'S EARS, and
// this is the entry that creates the second caller -- the same reason
// `Observation` is a file. The rule it enforces is not a formatting one: the two
// commands MUST NOT differ here, and written out twice they would, quietly, the
// first time one of them was reworded. A shared function makes them differ only
// by being edited on purpose.
//
// THERE IS NO HUMAN CHANNEL IN THIS BUILD. protocol.md §5 says `announce` is
// spoken to the human at the reader before the command acts, on the same side
// channel as the `announce` command -- and that channel is the `Announcer` port,
// which arrives with the control dialog at 13.10 along with the `interact`
// capability.
//
// SO THE FIELD IS HANDLED BY MODE, AND THE ASYMMETRY IS THE ONE THE HANDSHAKE
// ALREADY MAKES. In a SILENT session `announce` is the human's ONLY channel --
// the reader is being rendered mute on their behalf -- so a warning that cannot
// be honoured is REFUSED rather than dropped: this bridge does not half-keep a
// promise about somebody's ears, which is the argument that kept silent mode
// itself refused until 13.6. In a LIVE session the human hears their machine
// anyway, the warning is a courtesy rather than the only signal, so it is
// recorded in the transcript and the command proceeds.

public enum HumanWarning {
	/// Warn the human about what is about to happen to their machine, or refuse
	/// to act.
	///
	/// CALLED BEFORE ANYTHING ELSE IN A MUTATING HANDLER -- before the params are
	/// validated any further, and before a single event goes out: if this session
	/// cannot tell the human what is about to happen to their machine, nothing
	/// should happen to it.
	///
	/// Whitespace is not an announcement, so it is treated as absence.
	public static func honour(_ context: SessionContext, _ announce: String) throws {
		let words = announce.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !words.isEmpty else { return }
		guard context.mode != .silent else {
			throw CommandError(
				"this session is silent and this build has no channel to the human at the reader, "
					+ "so `announce` cannot be spoken -- and a silent session is the one place it is "
					+ "the only warning they would get. Send the same call with `announce` empty to "
					+ "proceed without warning them. The human channel arrives with the control "
					+ "dialog, which is also where the `interact` capability is announced"
			)
		}
		context.transcript.note(
			"announce (not spoken -- this build has no human channel; the session is live, so the "
				+ "reader is audible): \(words)")
	}
}
