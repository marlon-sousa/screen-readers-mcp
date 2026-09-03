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
// FOUR CASES SINCE 13.31, WHERE THERE WERE FIVE. `scriptingChannelDead` -- "the
// reader answers its own name but not its own state" -- was spec 0041's sharpest
// finding about the AppleScript channel, and it named a condition this bridge can
// no longer be in: the command-name route is deleted and no AppleEvent is sent
// anywhere (spec 0055). A named condition nothing can reach is worse than no
// condition at all, because an agent will try to interpret it.
//
// AND FIVE AGAIN SINCE 13.24 -- BUT THE FIFTH IS A DIFFERENT SHAPE, which is
// worth reading before adding a sixth. The four above are about OUR capture
// voice and the reader, so `ProviderState` decides which are live.
// `usersVoiceNotAvailable` is about the PERSON'S OWN voice, which no state of
// ours has an opinion about, so it is read directly by its two callers and
// appears in neither mapping below. See the case's own comment.
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

	/// VoiceOver is not running, or is not answering at all.
	///
	/// IT USED TO BE HALF OF A PAIR: `scriptingChannelDead` sat below it and meant
	/// "there, but not answering about itself", and keeping the two apart was the
	/// point of both. 13.31 deleted that one with the channel it described, so this
	/// is now the only question worth asking about the reader's existence -- and it
	/// is answered from the running-application list, at no permission cost.
	///
	/// NAMED AT 13.20, which is the entry that first needs a reader before it can
	/// do anything else. The bridge ACTIVATES the reader itself and asks again
	/// before reporting this, so by the time an agent reads it the easy half has
	/// already been tried.
	case readerNotRunning

	/// The voice the PERSON chose is not one this machine publishes any more --
	/// 13.24.
	///
	/// ============================================================================
	/// THE FIRST CASE HERE THAT IS NOT ABOUT THE CAPTURE VOICE, AND NO
	/// `ProviderState` MAPS TO IT.
	/// ============================================================================
	///
	/// Every other case describes where OUR voice has got to, so `ProviderState`
	/// owns which of them are live. This one describes the user's own voice, which
	/// no state of ours has an opinion about -- so it is read directly, by
	/// `ReaderEdgeSetup` at rung 4 and by `Session` at teardown. That asymmetry is
	/// written down here rather than left for somebody to find surprising, and it is
	/// the reason this case is not in `conditions` or `unheardConditions`.
	///
	/// IT IS NOT A REFUSAL. Spec 0056 §2.2, decided by Marlon on 2026-09-03: a
	/// session on a machine whose owner's voice has been removed ESTABLISHES, in
	/// both modes, and the person is told. The machine was already in that state
	/// before the session connected, the session did not cause it and cannot fix it,
	/// and refusing would deny testing on a reader that is otherwise capable of
	/// everything the session wants -- while putting nothing back. What this entry
	/// kills is the SILENCE, not the fallback.
	///
	/// AND ITS RECOVERY IS THE ONE THING THE PERSON HAS TO DO, which is why Marlon's
	/// answer named it: *"that handshake announcement must let the user know and
	/// give them instructions to install the voice."* It is SPOKEN, through the
	/// bridge's own synthesizer, which is audible even in a silent session.
	case usersVoiceNotAvailable

	/// What has gone wrong, in one sentence, for a reader of the transcript.
	public var summary: String {
		switch self {
		case .usersVoiceNotAvailable:
			return
				"the voice you had chosen is not one this machine publishes any more, so the reader "
				+ "will speak with its default voice instead"
		case .captureVoiceNotSelected:
			return "VoiceOver is not speaking with the capture voice, so nothing it says can be captured"
		case .captureVoiceNotOfferedByReader:
			return
				"the capture voice is published system-wide, but whether VoiceOver offers it cannot be read"
		case .providerNotRunning:
			return "the capture voice's speech provider is not registered, not enabled, or has died"
		case .readerNotRunning:
			return "VoiceOver is not running, or is not answering at all"
		}
	}

	/// What a human has to do about it. Measured, not guessed -- see the header.
	public var recovery: String {
		switch self {
		case .usersVoiceNotAvailable:
			// SPELLED IN FULL, because this is the one recovery in this file a person
			// carries out in a settings pane rather than at a keyboard, and a
			// half-named path is a path somebody hunts for. It is also the sentence
			// this bridge SPEAKS, so it has to read aloud as an instruction.
			//
			// IT DOES NOT PROMISE THE VOICE WILL WORK ONCE INSTALLED. The list this
			// condition is derived from publishes voices that are advertised and not
			// installed (13.15), so "install it" is the action and "the reader will
			// sound right again" is not a claim this bridge can make. See
			// `ProviderLifecycle.systemPublishesVoice`.
			return
				"install it again under System Settings > Accessibility > Spoken Content > System "
				+ "Voice > Manage Voices, or choose another voice there. Nothing needs restarting: "
				+ "the selection applies live. This session is running normally in the meantime, and "
				+ "it will put the same choice back when it ends"
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
