// A hand-written stateful fake for the SessionSignals port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/SessionSignals.swift.
//
// IT CAN BE TOLD TO FAIL, and that is its most useful mode: every call the
// session makes to a cue is guarded, and the only way to prove a guard works is
// to have the thing behind it throw. A session whose start cue failed must still
// be established, and one whose end cue failed must still have closed its
// channel.

import VoiceOverBridgeDomain

public final class FakeSessionSignals: SessionSignals {
	/// Something an audio device does when it is not there.
	public struct CueFailed: Error {
		public init() {}
	}

	public private(set) var startedWith: [String] = []
	public private(set) var endedCount = 0
	/// When true, both cues throw AFTER recording that they were asked -- so a
	/// test can assert both that the session tried and that it survived.
	public var fails = false

	public init() {}

	public func sessionStarted(persona: String) throws {
		startedWith.append(persona)
		if fails { throw CueFailed() }
	}

	public func sessionEnded() throws {
		endedCount += 1
		if fails { throw CueFailed() }
	}
}
