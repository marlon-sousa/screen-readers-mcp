// ROLE: supporting construct, the one mapping from SpeechBuffer entries to wire speech entries.
// USED BY: GetSpeech, PressGesture and TypeText.
// `logPosition` is always 0: VoiceOver has no diagnostic log journal to position into.

import ScreenReaderWire

public enum Observation {
	/// Entries that render empty are skipped, so each carries its own ring index, the coordinate an
	/// agent resumes from.
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
