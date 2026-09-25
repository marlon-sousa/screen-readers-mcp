// Hand-written stateful fake for the SilenceControl port; it records the sequence of acts.

import VoiceOverBridgeDomain

public final class FakeSilenceControl: SilenceControl {
	public enum Act: Equatable {
		case begin(preferredVoice: String?)
		case suppress
		case passThrough
		case renew
		case release
	}

	public struct WriteFailed: Error {
		public init() {}
	}

	public private(set) var acts: [Act] = []
	public private(set) var suppressing = false
	/// When true, everything that can throw does, after recording that it was asked.
	public var fails = false

	public init() {}

	public var isSuppressing: Bool { suppressing }

	public private(set) var preferredVoice: String?

	public func begin(preferredVoice: String?) throws {
		acts.append(.begin(preferredVoice: preferredVoice))
		self.preferredVoice = preferredVoice
		suppressing = false
		if fails { throw WriteFailed() }
	}

	public func suppress() throws {
		acts.append(.suppress)
		suppressing = true
		if fails { throw WriteFailed() }
	}

	public func passThrough() throws {
		acts.append(.passThrough)
		suppressing = false
		if fails { throw WriteFailed() }
	}

	public func renew() {
		acts.append(.renew)
	}

	public func release() {
		acts.append(.release)
		suppressing = false
	}

	public var renewals: Int { acts.filter { $0 == .renew }.count }
}
