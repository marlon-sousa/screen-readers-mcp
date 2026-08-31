// A hand-written stateful fake for the PlistReader adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/PlistReader.swift.
//
// An in-memory filesystem of exactly two questions: what is in the plist at a
// path, and whether something exists at one. It RECORDS THE PATHS ASKED FOR,
// which is most of the point -- the adapter above it is only correct if it asks
// about the two locations `scripts/voiceover_channels.sh` reads, and a fake that
// answered without saying what it was asked could not check that.

import VoiceOverBridgeAdapters

public final class FakePlistReader: PlistReader {
	public var plists: [String: [String: Any]] = [:]
	public var files: Set<String> = []
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
}
