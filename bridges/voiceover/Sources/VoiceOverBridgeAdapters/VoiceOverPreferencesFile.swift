// ROLE: supporting construct -- the ONE place that knows where VoiceOver keeps
// its own preferences. Pure: it derives paths from a home directory and does no
// IO.
//
// NOT AN ADAPTER AND NOT A PORT. It implements nothing and holds nothing; it is
// a named derivation two adapters share -- VoiceOverPrefsScriptingSetting, which
// asks whether AppleScript control is on, and VoiceOverPrefsModifierSetting,
// which asks what the VoiceOver modifier is bound to. Both read the same file
// through the same PlistReader seam.
//
// IT EXISTS BECAUSE THERE IS NOW A SECOND CALLER (13.25). While there was one,
// the path was a static on that class and that was right. Two adapters each
// carrying their own copy of a path is how two adapters come to disagree about
// where a file is -- and this file's whole content is a fact that has already
// moved once.
//
// A GROUP CONTAINER, NOT `~/Library/Preferences`, AND THAT IS THE FACT WORTH
// KNOWING. VoiceOver's settings live in the group container it shares with its
// helpers, which is why a sweep of the obvious location finds nothing (spec 0047,
// findings 10 and 16 are the same lesson from the other end -- the VOICE is in
// the system speech domain and not here at all).
//
// AND SEQUOIA *MOVED* THE FILE RATHER THAN ADDING A SECOND ONE, which is the
// opposite of what the AppleScript switch did with its marker file. So both paths
// are offered, newest first, and a caller reads them in order: a machine that was
// upgraded may still carry the older one, and looking costs nothing.

/// Where VoiceOver keeps `default.plist`, derived from a home directory.
///
/// `home` is passed in rather than read here, like every other derivation in this
/// bridge: Wiring is the one place that reads the environment, and everything
/// below that line is a pure function of values.
public enum VoiceOverPreferencesFile {
	/// The group container, which is where Sequoia and later keep it.
	public static func current(home: String) -> String {
		home
			+ "/Library/Group Containers/group.com.apple.VoiceOver/Library/Preferences"
			+ "/com.apple.VoiceOver4/default.plist"
	}

	/// Where it lived before Sequoia moved it.
	public static func legacy(home: String) -> String {
		home + "/Library/Preferences/com.apple.VoiceOver4/default.plist"
	}

	/// Both, newest first -- the order a caller should try them in.
	public static func candidates(home: String) -> [String] {
		[current(home: home), legacy(home: home)]
	}
}
