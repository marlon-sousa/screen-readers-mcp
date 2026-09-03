// A hand-written stateful fake for the ReaderLiveness port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/ReaderLiveness.swift.
//
// It counts the asks as well as answering them, and the count is the point: the
// port's own header says it is asked ONLY after a dispatch has already failed,
// because every real call is a subprocess. A fake that answered without counting
// would let a handler ask before every gesture and no test would notice.

import VoiceOverBridgeDomain

public final class FakeReaderLiveness: ReaderLiveness {
	/// What it answers. Defaults to the healthy reader, because that is the state
	/// nearly every test is in.
	public var isRunning: Bool
	public private(set) var asked = 0
	public private(set) var activations = 0

	/// What `activate()` makes of the reader. Defaults to "it comes up", because
	/// that is what `open -a VoiceOver` does on a working machine -- and a fake
	/// that could not model it could not tell a handshake that starts the reader
	/// from one that gives up on it.
	public var activationSucceeds = true

	public init(isRunning: Bool = true) {
		self.isRunning = isRunning
	}

	public func readerIsRunning() -> Bool {
		asked += 1
		return isRunning
	}

	/// COUNTED, and the count is the point: `activate()` may be called only when
	/// the reader did not answer. A fake that started the reader silently would
	/// let a handshake run `open -a VoiceOver` on every connect, and no test would
	/// notice a session that keeps taking somebody's screen over.
	public func activate() {
		activations += 1
		if activationSucceeds { isRunning = true }
	}
}
