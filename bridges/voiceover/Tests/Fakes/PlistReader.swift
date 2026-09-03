// A hand-written stateful fake for the PlistReader adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/PlistReader.swift.
//
// An in-memory filesystem of three questions: what is in the plist at a path,
// whether something exists at one, and which format it is in. It RECORDS THE
// PATHS ASKED FOR,
// which is most of the point -- the adapter above it is only correct if it asks
// about the two locations `scripts/voiceover_channels.sh` reads, and a fake that
// answered without saying what it was asked could not check that.

import Foundation
import VoiceOverBridgeAdapters

public final class FakePlistReader: PlistReader {
	public var plists: [String: [String: Any]] = [:]
	public var files: Set<String> = []
	/// Overrides for `format`, per path. Unset means binary -- see `format`.
	public var formats: [String: PropertyListSerialization.PropertyListFormat] = [:]
	public private(set) var reads: [String] = []
	public private(set) var existenceChecks: [String] = []

	public init() {}

	public func read(at path: String) -> [String: Any]? {
		reads.append(path)
		return plists[path]
	}

	public func exists(at path: String) -> Bool {
		existenceChecks.append(path)
		return files.contains(path)
	}

	/// BINARY BY DEFAULT, because VoiceOver's own preferences are binary on the
	/// maintainer's machine -- so the default here is the case a test is least
	/// likely to remember to set up and most likely to get wrong. A path with no
	/// plist has no format, exactly as the real leaf answers.
	public func format(at path: String) -> PropertyListSerialization.PropertyListFormat? {
		guard plists[path] != nil else { return nil }
		return formats[path] ?? .binary
	}
}
