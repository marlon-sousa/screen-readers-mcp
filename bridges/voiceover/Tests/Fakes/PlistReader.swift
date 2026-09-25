// Hand-written stateful fake for the PlistReader adapter seam; it records the paths asked for.

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
