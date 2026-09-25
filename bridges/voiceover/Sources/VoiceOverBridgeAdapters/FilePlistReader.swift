// ROLE: leaf adapter implementing the PlistReader seam over Foundation.
// BUILT BY: Wiring.
// USED BY: VoiceOverPrefsModifierSetting.
// Absent, unreadable and not-a-dictionary all return nil.

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
