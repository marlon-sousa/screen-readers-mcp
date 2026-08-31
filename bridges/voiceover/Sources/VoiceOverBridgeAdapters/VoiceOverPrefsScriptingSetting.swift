// ROLE: adapter -- IMPLEMENTS the ReaderScriptingSetting domain port. It knows
// the two places macOS records "AppleScript control of VoiceOver is on", and
// what their combinations mean.
//
// BUILT BY: Wiring, once per process. USED BY: the control dialog's
// preconditions section, through the port. HOLDS: the PlistReader seam.
//
// SEQUOIA *ADDED* THE FIRST LOCATION, IT DID NOT REPLACE THE SECOND, and that is
// the fact this class exists to encode. `scripts/voiceover_channels.sh` reads
// both and is the instrument this agrees with -- one probe for one question, so
// a human diagnosing a machine and this adapter cannot come to different
// conclusions about it:
//
//   * `~/Library/Group Containers/group.com.apple.VoiceOver/Library/Preferences/
//     com.apple.VoiceOver4/default.plist`, key `SCREnableAppleScript`.
//   * `/private/var/db/Accessibility/.VoiceOverAppleScriptEnabled`, a marker file
//     whose PRESENCE is the value.
//
// EITHER ONE SAYING YES IS A YES. They are two spellings of one switch, and a
// machine that has been upgraded can carry the older one alone.
//
// AND NEITHER ONE BEING READABLE IS `unknown`, NOT `disabled`. VoiceOver's
// preferences record only deviations from default and the marker is a file this
// process may simply not be allowed to see, so "I looked and found nothing" and
// "I could not look" are different answers -- and only one of them should send a
// human to VoiceOver Utility. The plist being READABLE and silent is a real
// `disabled`, because the switch ships off and a deviation would have been
// recorded.
//
// IT NEVER WRITES. There is no API that sets this switch, which is exactly what
// makes it a `Precondition` rather than a `Permission` -- see that entity.

import Foundation
import VoiceOverBridgeDomain

public final class VoiceOverPrefsScriptingSetting: ReaderScriptingSetting {
	/// The key Sequoia writes into VoiceOver's own preferences.
	static let preferencesKey = "SCREnableAppleScript"

	/// The marker file older systems record the same switch as. Absolute, and not
	/// derived from a home directory: it is a system location.
	public static let legacyMarkerPath = "/private/var/db/Accessibility/.VoiceOverAppleScriptEnabled"

	private let reader: any PlistReader
	private let home: String

	/// `home` is passed in rather than read here, like every other derivation in
	/// this bridge: Wiring is the one place that reads the environment, and
	/// everything below that line is a pure function of values.
	public init(reader: any PlistReader, home: String) {
		self.reader = reader
		self.home = home
	}

	/// Where VoiceOver keeps the preference, derived from a home directory.
	///
	/// A GROUP CONTAINER, not `~/Library/Preferences`: VoiceOver's own settings
	/// live in the group container it shares with its helpers, which is why a
	/// sweep of the obvious location finds nothing (spec 0047, findings 10 and 16
	/// are the same lesson from the other end -- the VOICE is in the system speech
	/// domain and not here at all).
	public static func preferencesPath(home: String) -> String {
		home
			+ "/Library/Group Containers/group.com.apple.VoiceOver/Library/Preferences"
			+ "/com.apple.VoiceOver4/default.plist"
	}

	public func scripting() -> ScriptingSetting {
		if reader.exists(at: VoiceOverPrefsScriptingSetting.legacyMarkerPath) {
			return .enabled
		}
		guard let preferences = reader.read(at: VoiceOverPrefsScriptingSetting.preferencesPath(home: home))
		else {
			return .unknown
		}
		guard let recorded = preferences[VoiceOverPrefsScriptingSetting.preferencesKey] else {
			// Readable, and the switch is not mentioned: it is at its default, and
			// the default is off.
			return .disabled
		}
		return VoiceOverPrefsScriptingSetting.isTrue(recorded) ? .enabled : .disabled
	}

	/// Whether a plist value means yes.
	///
	/// SPELLED OUT RATHER THAN CAST TO `Bool`, because a plist boolean arrives as
	/// an NSNumber and a plist written by a shell one-liner arrives as a STRING --
	/// the same type trap that made a correct-looking voice write vanish (spec
	/// 0047, finding 17). A `as? Bool` here would read `"1"` as "not a boolean"
	/// and report a machine with the switch on as off.
	static func isTrue(_ value: Any) -> Bool {
		if let flag = value as? Bool { return flag }
		if let number = value as? NSNumber { return number.boolValue }
		if let text = value as? String {
			return ["1", "true", "yes"].contains(text.lowercased())
		}
		return false
	}
}
