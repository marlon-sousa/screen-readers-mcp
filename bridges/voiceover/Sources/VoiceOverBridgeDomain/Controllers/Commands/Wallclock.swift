// ROLE: a pure function that turns an epoch stamp into the protocol's one timestamp string.
// USED BY: the GetSpeech, GetLastSpeech and WaitForSpeech handlers, for `emittedAt`.
// The same format the transcript writes, so a stamp can be searched for there; it is not ISO 8601.

import Foundation

public enum Wallclock {
	/// Render epoch seconds as `YYYY-MM-DD HH:MM:SS.mmm` in the machine's own
	/// time zone -- the zone the transcript beside it is written in.
	/// `0` is the buffer's sentinel for "no instant recorded" and renders as the empty string.
	public static func format(_ epoch: Double) -> String {
		guard epoch != 0 else { return "" }
		return formatter.string(from: Date(timeIntervalSince1970: epoch))
	}

	/// Built once: a DateFormatter costs milliseconds to construct.
	private static let formatter: DateFormatter = {
		let formatter = DateFormatter()
		// POSIX, so a non-Gregorian calendar setting still yields the contract's shape.
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
		return formatter
	}()
}
