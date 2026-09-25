// ROLE: supporting construct, the one place that knows where VoiceOver keeps its own preferences; pure, no IO.
// USED BY: VoiceOverPrefsModifierSetting.
// On macOS 15 VoiceOver's settings live in its group container, not `~/Library/Preferences`, and the voice is not here at all (see SpeakSelectionVoiceStore).
// macOS 15 moved the file rather than adding one, so an upgraded machine may still carry the older copy.

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
