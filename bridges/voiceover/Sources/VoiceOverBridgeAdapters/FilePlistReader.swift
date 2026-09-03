// ROLE: LEAF adapter -- IMPLEMENTS the PlistReader seam over Foundation. Real
// files, no decisions.
//
// BUILT BY: Wiring. USED BY: VoiceOverPrefsScriptingSetting, which holds every
// decision about what it reads.
//
// NO TEST FILE (leaf): there is nothing here that `NSDictionary(contentsOfFile:)`
// and `FileManager.fileExists` do not already guarantee. If you are adding a
// test here, a decision has landed in a leaf and belongs one layer up.
//
// IT SWALLOWS ITS OWN FAILURES INTO `nil`, which is the seam's contract: absent,
// unreadable, and not-a-dictionary are one answer here, and the adapter above
// turns that answer into `unknown` rather than into `disabled`.
//
// AND SINCE 13.26 IT ALSO REPORTS THE ON-DISK FORMAT, because
// `VoiceOverPrefsModifierStore` writes one key of VoiceOver's own preferences
// back and must not change the file's shape while doing it. See the seam.

import Foundation

public final class FilePlistReader: PlistReader {
	public init() {}

	public func read(at path: String) -> [String: Any]? {
		NSDictionary(contentsOfFile: path) as? [String: Any]
	}

	public func exists(at path: String) -> Bool {
		FileManager.default.fileExists(atPath: path)
	}

	/// The on-disk format, learned by parsing the file and asking for it back.
	///
	/// `propertyList(from:options:format:)` reports what it found, which is the
	/// only way to learn this: there is no "what format is this file" API. The
	/// parse is thrown away -- the caller has already read the contents through
	/// `read` -- because a seam method that returned both would be a decision
	/// about how the two are used, and that belongs above this line.
	public func format(at path: String) -> PropertyListSerialization.PropertyListFormat? {
		guard let data = FileManager.default.contents(atPath: path) else { return nil }
		var found = PropertyListSerialization.PropertyListFormat.binary
		guard (try? PropertyListSerialization.propertyList(from: data, options: [], format: &found)) != nil
		else { return nil }
		return found
	}
}
