// Hand-written stateful fake for the SessionSignals port.

import VoiceOverBridgeDomain

public final class FakeSessionSignals: SessionSignals {
	public struct CueFailed: Error {
		public init() {}
	}

	public private(set) var startedWith: [String] = []
	public private(set) var endedCount = 0
	public private(set) var warnedCount = 0
	public private(set) var liftedCount = 0
	/// When true, every cue throws after recording that it was asked.
	public var fails = false
	public private(set) var resuppressedCount = 0

	public init() {}

	public func sessionStarted(persona: String) throws {
		startedWith.append(persona)
		if fails { throw CueFailed() }
	}

	public func sessionEnded() throws {
		endedCount += 1
		if fails { throw CueFailed() }
	}

	public func silenceWarning() throws {
		warnedCount += 1
		if fails { throw CueFailed() }
	}

	public func silenceLifted() throws {
		liftedCount += 1
		if fails { throw CueFailed() }
	}

	public func silenceResuppressed() throws {
		resuppressedCount += 1
		if fails { throw CueFailed() }
	}
}
