// ROLE: a pure function, not a class. No state, no collaborators, no IO -- it
// turns an epoch stamp into the one string shape this protocol uses.
//
// USED BY: the GetSpeech, GetLastSpeech and WaitForSpeech handlers, for
// `emittedAt`. It is a file of its own for the reason lane 1's `wallclock.py` is
// one: three renderings of one format is one format until somebody edits one of
// them, and spec 0028 extracted exactly this function there after two copies
// had already drifted.
//
// AN AMENDMENT TO SPEC 0046's 13.5 LAYOUT, with its why: the layout gives the
// five handlers and no shared helper, because rendering looked like a line of
// code rather than a decision. It is a decision -- WHICH format, and what an
// unstamped entry renders as -- and it is made in three places.
//
// WHY THIS FORMAT: `YYYY-MM-DD HH:MM:SS.mmm` is what protocol.md §7.1 states,
// what the Python bridge's `format_wallclock` produces, and what this bridge's
// own FileTranscript writes on every line. Half the value of reporting a wall
// clock at all is joining artefacts stamped by somebody else, so a stamp an
// agent reads back can be pasted straight into a search of the transcript. It is
// NOT ISO 8601, whatever a reader of the field's name might assume.

import Foundation

public enum Wallclock {
	/// Render epoch seconds as `YYYY-MM-DD HH:MM:SS.mmm` in the machine's own
	/// time zone -- the zone the transcript beside it is written in.
	///
	/// `0` renders as the EMPTY STRING rather than as 1970. Zero is the buffer's
	/// sentinel and the answer for an out-of-range index, and it means *no
	/// instant was recorded*: an empty string says that, and a date fifty years
	/// ago actively misleads about it (spec 0028, protocol.md §7.1).
	public static func format(_ epoch: Double) -> String {
		guard epoch != 0 else { return "" }
		return formatter.string(from: Date(timeIntervalSince1970: epoch))
	}

	/// Built once. A DateFormatter costs milliseconds to construct and every
	/// entry of a long `getSpeech` would pay it.
	private static let formatter: DateFormatter = {
		let formatter = DateFormatter()
		// POSIX, so a machine configured for a non-Gregorian calendar still
		// produces the shape the contract states.
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
		return formatter
	}()
}
