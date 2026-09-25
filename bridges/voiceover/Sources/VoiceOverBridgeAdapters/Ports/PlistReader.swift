// ROLE: adapter seam that reads a property list and says whether a file is there.
// IMPLEMENTED BY: FilePlistReader and FakePlistReader.
// USED BY: VoiceOverPrefsModifierSetting, which decides what the files mean.
// Read-only on purpose: on macOS 15, writing the VoiceOver modifier under a running VoiceOver raises a modal question that blocks it from quitting.

public protocol PlistReader: AnyObject {
	/// The whole plist at `path`, or nil when it cannot be read as one.
	func read(at path: String) -> [String: Any]?

	func exists(at path: String) -> Bool
}
