// ROLE: port -- take the reader away and bring it back.
// IMPLEMENTED BY: VoiceOverRestart, over the RunningApplications seam and a ProcessRunner; FakeReaderRestart.
// BUILT BY: VoiceOverAdapterFactory.
// USED BY: ReaderEdgeSetup's registration rung only; no command handler may reach it.
// Callers restart only for a named reason, and announce it first through the bridge's own synthesizer: this port makes no sound.
// `killall VoiceOver` alone does not relaunch the reader, and `killall && open -a` races the shutdown, so quit, poll until the process is gone, then open.

public struct ReaderRestartError: Error, Equatable, CustomStringConvertible {
	public let description: String

	/// Whether the reader is believed running despite the failure: a reader that did not come back leaves a person with no screen reader.
	public let readerStillRunning: Bool

	public init(_ description: String, readerStillRunning: Bool) {
		self.description = description
		self.readerStillRunning = readerStillRunning
	}
}

public protocol ReaderRestart: AnyObject {
	/// Blocks until the reader is back, or throws.
	func restart() throws
}
