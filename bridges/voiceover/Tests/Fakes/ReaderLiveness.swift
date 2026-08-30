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
	public var answersItsOwnName: Bool
	public private(set) var asked = 0

	public init(answersItsOwnName: Bool = true) {
		self.answersItsOwnName = answersItsOwnName
	}

	public func readerAnswersItsOwnName() -> Bool {
		asked += 1
		return answersItsOwnName
	}
}
