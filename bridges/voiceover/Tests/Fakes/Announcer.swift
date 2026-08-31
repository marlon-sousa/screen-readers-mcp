// A hand-written stateful fake for the Announcer port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/Announcer.swift.
//
// IT EXISTS TO MAKE ONE MISTAKE UNAVAILABLE: no test may speak. A real
// synthesizer in a test talks over the developer, which is the same class of
// mistake as typing into their frontmost window -- and it would do it while they
// are reading the failure.
//
// IT RECORDS WHAT WOULD HAVE BEEN SAID, in order, because that is the assertion
// this entry's whole promise rests on: `announce` in a SILENT session is the
// human's only channel, and what proves it was kept is that the words reached
// this port rather than the reader.

import VoiceOverBridgeDomain

public final class FakeAnnouncer: Announcer {
	/// Something a loudspeaker does when it is not there.
	public struct SpeechFailed: Error {
		public init() {}
	}

	public private(set) var spoken: [String] = []

	/// When true, `announce` throws AFTER recording the attempt -- so a test can
	/// assert both that the bridge tried and what it did about the failure.
	public var fails = false

	public init() {}

	public func announce(_ text: String) throws {
		spoken.append(text)
		if fails { throw SpeechFailed() }
	}
}
