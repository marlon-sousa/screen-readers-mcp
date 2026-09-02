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
	/// The silence cap's two cues, counted separately: a warning that was never
	/// spoken and a lift that was never marked are different failures.
	public private(set) var warnedCount = 0
	public private(set) var liftedCount = 0
	/// When true, both cues throw AFTER recording that they were asked -- so a
	/// test can assert both that the session tried and that it survived.
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

	/// COUNTED SEPARATELY FROM THE LIFT, and the count is the point: the defect
	/// this method exists for was a session that lifted once and stayed audible
	/// forever, so "it went quiet again, and how many times" is exactly what a
	/// test has to be able to ask.
	public func silenceResuppressed() throws {
		resuppressedCount += 1
		if fails { throw CueFailed() }
	}
}
