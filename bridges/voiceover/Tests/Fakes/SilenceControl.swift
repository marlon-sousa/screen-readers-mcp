// A hand-written stateful fake for the SilenceControl port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/SilenceControl.swift.
//
// IT RECORDS THE SEQUENCE, not just the final state, because the ORDER is what
// the session's tests are about: the channel is opened before it is suppressed,
// the lease is renewed while the session lives, and it is released on every
// teardown path -- and a fake that only remembered "suppressing: false" at the
// end could not tell a session that released it from one that never suppressed.
//
// IT CAN BE TOLD TO FAIL, which is the only way to prove that a teardown step
// that throws does not skip the ones after it.

import VoiceOverBridgeDomain

public final class FakeSilenceControl: SilenceControl {
	public enum Act: Equatable {
		case begin(preferredVoice: String?)
		case suppress
		case passThrough
		case renew
		case release
	}

	/// Something a filesystem does when the container is not there.
	public struct WriteFailed: Error {
		public init() {}
	}

	public private(set) var acts: [Act] = []
	public private(set) var suppressing = false
	/// When true, everything that can throw does -- AFTER recording that it was
	/// asked, so a test can assert both that the bridge tried and that it survived.
	public var fails = false

	public init() {}

	public var isSuppressing: Bool { suppressing }

	/// The voice the bridge handed the extension, as of the last `begin`.
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

	/// How many times the lease was re-armed, which is what "while the session
	/// lives" means in a test.
	public var renewals: Int { acts.filter { $0 == .renew }.count }
}
