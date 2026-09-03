// ROLE: entity -- the named conditions this reader can be in, each with the
// recovery a human would have to perform.
//
// PURE, and the smallest file in the bridge that carries the most argument. It
// is spec 0041's sharpest requirement made structural:
//
//   "A bridge on this route must treat [this] as a distinct, detectable,
//    reported condition -- returning an empty read-back is what a naive
//    implementation does, and it is wrong."
//
// An empty read-back is the same answer for "the reader said nothing", "the
// provider died", "the voice is not selected" and "VoiceOver never offered the
// voice at all". Four different situations, three of them repairable, one of
// them normal -- and an agent that cannot tell them apart concludes the reader
// is silent and reports a bug that does not exist.
//
// USED BY: ProviderState, which says which of these are live for a given state;
// the Hello handler, which refuses a silent session naming one; the two waiting
// speech handlers, which name one instead of answering "not found"; and the
// transcript, so the human reading it afterwards sees the same words the agent
// did.
//
// EACH CASE CARRIES ITS OWN RECOVERY, and that is why this is an entity rather
// than a string in a handler: the recovery for a lost voice was MEASURED (spec
// 0047, finding 6) and is not the obvious one -- restarting the reader is
// necessary and NOT sufficient, re-registration comes first, and getting that
// order wrong wastes a person's afternoon on a reader that keeps not working.
//
// AND SINCE 13.20 THE BRIDGE PERFORMS THE FIRST HALF OF THAT RECOVERY ITSELF, so
// these sentences had to change or they would be telling a human to do something
// that has already been done. `hello` registers the extension and selects the
// voice before it answers (spec 0050), which leaves exactly ONE action in a
// human's hands -- the reader restart, which publishes a newly registered voice
// and which no handshake may take on somebody's behalf. So each recovery below
// now says what the bridge already tried and names the one thing it may not.
//
// THE RESTART IS ALWAYS SPELLED AS A PAIR, and that is not tidiness. MEASURED
// 2026-08-31: `killall VoiceOver` does NOT relaunch the reader -- it leaves a
// blind person with no screen reader at all, and `open -a VoiceOver` is what
// brings it back. A recovery that said "restart VoiceOver" is a recovery
// somebody could follow into silence, so every one of them below goes through
// `readerRestartCommand` rather than spelling it again.

public enum ReaderCondition: String, Equatable, Sendable, CaseIterable {
	/// The capture voice is not what VoiceOver is speaking with, so nothing this
	/// bridge does can be heard, silenced or captured.
	case captureVoiceNotSelected

	/// The voice is published system-wide and VoiceOver is nonetheless not
	/// offering it. Spec 0047, finding 6, and the worst-shaped of the three:
	/// nothing observable from outside the reader distinguishes it from health.
	case captureVoiceNotOfferedByReader

	/// The speech provider is not registered, not enabled, or has died. VoiceOver
	/// falls back to a working voice rather than to silence (spec 0041, C2), so
	/// this is degraded rather than dangerous -- and it is invisible to the ear,
	/// because pass-through re-speaks with the very voice a failure falls back to
	/// (spec 0047, finding 18).
	case providerNotRunning

	/// VoiceOver is not running, or is not answering at all -- which is a
	/// different thing from the case below it, and the two have different
	/// recoveries.
	///
	/// NAMED AT 13.20, which is the entry that first needs a reader before it can
	/// do anything else. The bridge ACTIVATES the reader itself and asks again
	/// before reporting this, so by the time an agent reads it the easy half has
	/// already been tried.
	case readerNotRunning

	/// VoiceOver answers its own name and nothing else: the scripting object
	/// model died without the reader dying (spec 0041, the input half).
	///
	/// NAMED HERE AND DETECTED BY 13.7, which is the entry that first speaks to
	/// the reader over that channel. It is written down now because this file is
	/// the vocabulary, and a condition that exists in a spec and in no type is
	/// one that gets rediscovered as an empty read-back.
	case scriptingChannelDead

	/// What has gone wrong, in one sentence, for a reader of the transcript.
	public var summary: String {
		switch self {
		case .captureVoiceNotSelected:
			return "VoiceOver is not speaking with the capture voice, so nothing it says can be captured"
		case .captureVoiceNotOfferedByReader:
			return
				"the capture voice is published system-wide, but whether VoiceOver offers it cannot be read"
		case .providerNotRunning:
			return "the capture voice's speech provider is not registered, not enabled, or has died"
		case .readerNotRunning:
			return "VoiceOver is not running, or is not answering at all"
		case .scriptingChannelDead:
			return "VoiceOver answers its own name but not its own state"
		}
	}

	/// What a human has to do about it. Measured, not guessed -- see the header.
	public var recovery: String {
		switch self {
		case .captureVoiceNotSelected:
			return
				"the bridge selects the capture voice itself at every handshake; if it did not stick, the "
				+ "voice is not in VoiceOver's list yet -- the bridge has already re-registered the "
				+ "extension, so what is left is to restart the reader: \(readerRestartCommand)"
		case .captureVoiceNotOfferedByReader:
			return
				"restart the reader -- \(readerRestartCommand) -- which is what publishes a newly "
				+ "registered voice to it. The bridge has already done the re-registration a restart "
				+ "alone was measured NOT to be enough without"
		case .providerNotRunning:
			return
				"the bridge registers the extension at every handshake (lsregister -f on the app, THEN "
				+ "pluginkit -a on the .appex); if this is still the answer, either those could not run "
				+ "-- the failure says so by name -- or the reader has not restarted since, and a "
				+ "restart is the only thing that re-binds the voice: \(readerRestartCommand)"
		case .scriptingChannelDead:
			return
				"restart the reader -- \(readerRestartCommand) -- because nothing short of a reader "
				+ "restart recovers the scripting channel"
		case .readerNotRunning:
			return
				"start VoiceOver: `open -a VoiceOver`, or Command-F5. The bridge tries this itself at "
				+ "the handshake, so if this is the answer the reader would not come up -- check "
				+ "whether it is asking for a password or showing a dialog on the machine's screen"
		}
	}

	/// The one rendering an agent or a transcript reader gets, so the name and its
	/// recovery never travel apart.
	public var described: String {
		"\(rawValue): \(summary). Recovery: \(recovery)."
	}
}

/// How a human restarts this reader, spelled as ONE string so it cannot be
/// half-quoted anywhere.
///
/// ============================================================================
/// IT SAID `killall VoiceOver && open -a VoiceOver` UNTIL 13.26, AND THAT LINE
/// WAS WRONG IN TWO WAYS. BOTH WERE PAID FOR.
/// ============================================================================
///
/// MEASURED 2026-08-31: `killall VoiceOver` on its own does NOT relaunch it. A
/// recovery that stopped after the kill would leave a blind person with no screen
/// reader and no obvious way back, which is the single worst thing any sentence
/// in this file could cause. That much was right, and it is why the two halves
/// were made to travel together.
///
/// WHAT IT MISSED IS THAT THE PAIR RACES. `killall` returns when the SIGNAL IS
/// SENT, not when the process is gone, so `open -a` can fire into a reader macOS
/// still believes is running -- and `open` on a running application does nothing
/// at all. The 2026-09-02 field report is very probably exactly that: following
/// this sentence left the reader in a state where every scripting call answered
/// `-1728`, and it cost about twenty minutes and an interruption of the blind user
/// at the machine before COMMAND-F5 fixed what `open -a` had not. Its ask, in as
/// many words: *"Either restart the reader the way that works, or print the
/// gesture that works."*
///
/// SO THIS IS THE GESTURE NOW, AND THE SHELL FORM IS SPELLED WITH ITS WAIT. The
/// audience for this string is a HUMAN AT THE MACHINE -- every sentence that
/// carries it reads "ask the human at this machine to ..." -- and what a person
/// presses to toggle VoiceOver is Command-F5. The bridge's own restarts do not go
/// through this string at all: they go through `ReaderRestart`, which quits, polls
/// until the process is gone, and only then starts it.
public let readerRestartCommand =
	"press Command-F5 twice -- once to stop VoiceOver and once to start it again. "
	+ "(From a terminal it is `killall VoiceOver`, then WAIT until "
	+ "`pgrep -x VoiceOver` finds nothing, then `open -a VoiceOver`. Do not join "
	+ "those with `&&`: killall returns as soon as the signal is sent, so `open` "
	+ "fires while the reader is still shutting down and does nothing at all.)"
