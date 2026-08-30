// ROLE: supporting construct in the controllers layer -- the one mapping from
// what the SpeechBuffer holds to what the wire publishes.
//
// USED BY: GetSpeech, PressGesture, and from 13.8 TypeText. No state and no IO,
// so it is a function on an enum rather than a class: there is nothing to hold.
//
// IT EXISTS BECAUSE THREE COMMANDS ASSEMBLE THE SAME ANSWER, which is lane 1's
// reason for the module of the same name, arriving here at the entry that
// creates the second caller. The buffer stores an emission stamp as a NUMBER and
// the wire publishes it as text, so this is the presentation step -- which is
// exactly why the entity never learned the format. Written out per command, the
// formatting or the index convention would be corrected in two places and missed
// in the third, which is the failure spec 0028 recorded when three `append`
// implementations each grew the same field by hand.
//
// WHAT LANE 1's VERSION HAS AND THIS DOES NOT: `state_snapshot`. This bridge
// announces no `state` capability -- VoiceOver's toggles are richly drivable and
// almost none is readable (spec 0046 part 2) -- so `GestureResult.state` stays
// nil and there is nothing to sample. Left out rather than stubbed, for the same
// reason an unimplemented port field is: a sampler that answered nothing would
// be a promise this build does not keep.
//
// `logPosition` IS ALWAYS 0, and that is the honest answer rather than a stub:
// it is a coordinate into NVDA's log journal, and VoiceOver emits no diagnostic
// log of its own to position into. The field stays in the shape because the
// shape is the contract's.

import ScreenReaderWire

public enum Observation {
	/// Map what the buffer handed back to the wire's speech entries.
	///
	/// Each entry carries its OWN index rather than being counted from the start
	/// of the list, because entries that render empty are skipped -- so position
	/// in this array and index in the ring are different numbers, and only one of
	/// them is a coordinate the agent can resume from.
	public static func speechEntries(
		_ entries: [(utterance: CapturedUtterance, index: Int)]
	) -> [SpeechEntry] {
		entries.map {
			SpeechEntry(
				text: $0.utterance.text,
				index: $0.index,
				logPosition: 0,
				emittedAt: Wallclock.format($0.utterance.emittedAt)
			)
		}
	}
}
