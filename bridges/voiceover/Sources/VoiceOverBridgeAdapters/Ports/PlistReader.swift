// ROLE: adapter seam -- read a property list, and say whether a file is there.
//
// NOT A DOMAIN PORT: the domain asks whether AppleScript control of the reader is
// switched on (`ReaderScriptingSetting`) and does not know that the answer is
// two files on disk.
//
// IMPLEMENTED BY: FilePlistReader (a leaf) and FakePlistReader (Tests/Fakes).
// USED BY: VoiceOverPrefsScriptingSetting, which is the one place that decides
// what the two files MEAN.
//
// TWO METHODS BECAUSE THE SETTING IS RECORDED TWO WAYS, and that is the measured
// shape rather than a general-purpose filesystem seam growing here: Sequoia
// writes a KEY into VoiceOver's own preferences, and older systems record the
// same fact as the PRESENCE of a marker file with nothing in it
// (`scripts/voiceover_channels.sh` reads both). A seam that only read plists
// would send the adapter to `FileManager` for the other half, which is the
// untestable half arriving through the back door.
//
// `nil` FROM `read` MEANS "COULD NOT BE READ", and the distinction is the whole
// reason the port above has three answers: a plist that is absent, unreadable or
// not a dictionary is not a machine where the setting is off.
//
// IT IS READ-ONLY, AND 13.26 IS WHY THAT IS WORTH SAYING OUT LOUD. That entry
// added a write side to it -- a `format` question here and a `PlistWriter` seam
// beside it -- so that the handshake could borrow the VoiceOver modifier on a
// machine bound to Caps Lock. THE LIVE RUN KILLED THAT DESIGN: writing the
// modifier under a running reader makes VoiceOver put a modal question on screen
// asking the person whether they wanted Control-Option, which blocks the reader
// from quitting and changes a setting nobody chose. Measured 2026-09-02 on the
// maintainer's machine, and the whole write side came back out. Nothing in this
// bridge writes VoiceOver's own preferences, and that is a property to keep.

public protocol PlistReader: AnyObject {
	/// The whole plist at `path`, or nil when it cannot be read as one.
	func read(at path: String) -> [String: Any]?

	/// Whether something exists at `path`. For a marker file, existence IS the
	/// value.
	func exists(at path: String) -> Bool
}
