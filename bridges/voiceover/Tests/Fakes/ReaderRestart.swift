// A hand-written stateful fake for the ReaderRestart port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/ReaderRestart.swift.
//
// It COUNTS RESTARTS, and the count is the point twice over. A restart takes a
// blind person's screen reader away for several seconds, so spec 0053 §3.2 binds
// it to a named reason -- and the only way to check "never speculatively" is a
// test that asserts the count is ZERO on an ordinary handshake. The other half is
// the modifier sequence, which costs exactly TWO: one to apply and one to put
// back.
//
// `onRestart` IS WHAT MAKES IT A REAL DOUBLE RATHER THAN A COUNTER. The reader
// re-reads its preferences when it comes up, so a test that drives the modifier
// rung has the fake move the read-side setting on restart -- which is the machine
// behaviour the whole sequence exists to work with (measured 2026-09-02: the
// modifier is read only at startup).

import VoiceOverBridgeDomain

public final class FakeReaderRestart: ReaderRestart {
	public private(set) var restarts = 0

	/// What the next restart does. A failure with `readerStillRunning: false` is
	/// the one a caller has to say something different about -- there is a person
	/// with no screen reader -- so it is modellable here.
	public var failure: ReaderRestartError?

	/// Called on each successful restart, so a test can move whatever the reader
	/// would have re-read.
	public var onRestart: (() -> Void)?

	public init() {}

	public func restart() throws {
		if let failure { throw failure }
		restarts += 1
		onRestart?()
	}
}
