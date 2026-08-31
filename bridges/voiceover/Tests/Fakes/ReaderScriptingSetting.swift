// A hand-written stateful fake for the ReaderScriptingSetting port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/ReaderScriptingSetting.swift.
//
// It answers whatever it is told to, and counts the asking: the dialog reads
// this on every refresh, and "did pressing Refresh actually re-read the machine?"
// is a question about a count rather than about a value.

import VoiceOverBridgeDomain

public final class FakeReaderScriptingSetting: ReaderScriptingSetting {
	public var setting: ScriptingSetting
	public private(set) var reads = 0

	public init(setting: ScriptingSetting = .enabled) {
		self.setting = setting
	}

	public func scripting() -> ScriptingSetting {
		reads += 1
		return setting
	}
}
