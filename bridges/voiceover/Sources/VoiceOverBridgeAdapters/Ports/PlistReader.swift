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
// AND A THIRD METHOD ARRIVED WITH 13.26, FOR A DIFFERENT REASON THAN THE FIRST
// TWO. `VoiceOverPrefsModifierStore` reads this file in order to WRITE one key of
// it back (through the separate `PlistWriter` seam), and a file rewritten in a
// format it was not already in is a file macOS still reads while every instrument
// in this repository suddenly disagrees with it. VoiceOver's own preferences are
// BINARY on the maintainer's machine. So the format is asked for explicitly and
// carried to the write, rather than the leaf quietly deciding -- which is the
// layering rule: the decision belongs above the seam, and "preserve what was
// there" is a decision.

import Foundation

public protocol PlistReader: AnyObject {
	/// The whole plist at `path`, or nil when it cannot be read as one.
	func read(at path: String) -> [String: Any]?

	/// Whether something exists at `path`. For a marker file, existence IS the
	/// value.
	func exists(at path: String) -> Bool

	/// Which on-disk format the plist at `path` is in, or nil when it cannot be
	/// read as one. See the header.
	func format(at path: String) -> PropertyListSerialization.PropertyListFormat?
}
