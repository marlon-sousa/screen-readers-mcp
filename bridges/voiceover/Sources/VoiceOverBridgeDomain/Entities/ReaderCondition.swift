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
		case .scriptingChannelDead:
			return "VoiceOver answers its own name but not its own state"
		}
	}

	/// What a human has to do about it. Measured, not guessed -- see the header.
	public var recovery: String {
		switch self {
		case .captureVoiceNotSelected:
			return
				"the bridge selects the capture voice itself at session start; if it did not stick, the "
				+ "voice is probably not in VoiceOver's list -- re-register the extension "
				+ "(lsregister -f on the app, THEN pluginkit -a on the .appex) and restart VoiceOver"
		case .captureVoiceNotOfferedByReader:
			return
				"re-register the extension (lsregister -f on the app, THEN pluginkit -a on the .appex) "
				+ "and restart VoiceOver -- a restart alone was measured NOT to be enough"
		case .providerNotRunning:
			return
				"register the extension (lsregister -f on the app, THEN pluginkit -a on the .appex) and "
				+ "restart VoiceOver, which is the only thing that re-binds the voice"
		case .scriptingChannelDead:
			return "restart VoiceOver; nothing short of a reader restart recovers the scripting channel"
		}
	}

	/// The one rendering an agent or a transcript reader gets, so the name and its
	/// recovery never travel apart.
	public var described: String {
		"\(rawValue): \(summary). Recovery: \(recovery)."
	}
}
