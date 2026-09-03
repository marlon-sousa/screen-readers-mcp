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


import Foundation

public final class FilePlistReader: PlistReader {
	public init() {}

	public func read(at path: String) -> [String: Any]? {
		NSDictionary(contentsOfFile: path) as? [String: Any]
	}

	public func exists(at path: String) -> Bool {
		FileManager.default.fileExists(atPath: path)
	}
}
