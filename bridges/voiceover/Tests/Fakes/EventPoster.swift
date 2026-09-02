// A hand-written stateful fake for the EventPoster adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/EventPoster.swift.
//
// IT RECORDS THE PAYLOAD AND WHICH HALF OF THE KEYSTROKE IT WAS, because both
// are decisions the layer above makes: how the text was cut into payloads, and
// that every chunk goes out as a down and then an up. A double that only
// collected the text would pass a typer that sent key-downs and no key-ups.
//
// AND SINCE 13.17 IT RECORDS THE SEAM'S OTHER TWO SHAPES SEPARATELY -- a keycode
// with modifier flags, and a modifier transition. They are kept in separate lists
// because they are separate events with separate callers, and a test that
// asserted a chord went out should not be satisfiable by a chunk of typed text.
//
// THE TRANSITIONS ARE RECORDED IN ORDER WITH THE KEY EVENTS, in `sequence`,
// because the ORDER is the whole property: hold, key down, key up, release. A
// double that collected them in two unrelated lists could not tell a presser that
// releases the modifier from one that leaves it down -- which is the bug this
// shape was added to prevent, after a live run left Command held on the
// maintainer's machine and made every subsequent keystroke a chord.
//
// AND NO TEST POSTS A REAL EVENT. The real poster types into whatever window is
// in front of the developer, so this is the only implementation any test may
// ever hold.

import CoreGraphics
import VoiceOverBridgeAdapters

public final class FakeEventPoster: EventPoster {
	public struct Posted: Equatable {
		public let unicode: String
		public let keyDown: Bool

		public init(unicode: String, keyDown: Bool) {
			self.unicode = unicode
			self.keyDown = keyDown
		}
	}

	/// One key event: a keycode with the flags held for it.
	public struct Keyed: Equatable {
		public let keyCode: UInt16
		public let flags: CGEventFlags
		public let keyDown: Bool

		public init(keyCode: UInt16, flags: CGEventFlags, keyDown: Bool) {
			self.keyCode = keyCode
			self.flags = flags
			self.keyDown = keyDown
		}
	}

	/// One event of any shape, in the order it went out.
	public enum Event: Equatable {
		case unicode(String, keyDown: Bool)
		case key(UInt16, flags: CGEventFlags, keyDown: Bool)
		case flags(UInt16, CGEventFlags)
	}

	public private(set) var posted: [Posted] = []
	public private(set) var keyed: [Keyed] = []
	public private(set) var sequence: [Event] = []

	/// Only the modifier transitions, which is what a test asserting the keyboard
	/// was left clean reads.
	public var flagTransitions: [CGEventFlags] {
		sequence.compactMap { if case .flags(_, let f) = $0 { return f } else { return nil } }
	}

	/// Set to make every call fail, which is how the typer's translation of a
	/// posting failure is exercised.
	public var failure: EventPostingFailure?

	public init() {}

	/// What was typed, reassembled -- the key-downs only, so the reassembly is
	/// not doubled by the key-ups.
	public var typedText: String {
		posted.filter(\.keyDown).map(\.unicode).joined()
	}

	/// Set to make only the KEY events fail, leaving the modifier transitions
	/// working -- which is how "the release still happens when the press failed"
	/// is exercised. A blanket `failure` would fail the release too and prove
	/// nothing.
	public var keyFailure: EventPostingFailure?

	/// Which single KEY event `keyFailure` applies to, counted from 1.
	///
	/// Nil means every one of them, which is what `keyFailure` meant before 13.22.
	/// Set to 2 and the first key of a two-key chord goes down, the second does
	/// not, and the RELEASE of the first still goes out -- which is the only way
	/// to exercise the property that entry added: a press that fails partway
	/// releases exactly the keys it managed to press, and no more.
	public var keyFailureAt: Int?

	/// Key events attempted, failures included -- which is what `keyFailureAt`
	/// counts. `keyed` holds only the ones that went out.
	private var keyAttempts = 0

	public func post(unicode: String, keyDown: Bool) throws {
		if let failure { throw failure }
		posted.append(Posted(unicode: unicode, keyDown: keyDown))
		sequence.append(.unicode(unicode, keyDown: keyDown))
	}

	public func post(keyCode: UInt16, flags: CGEventFlags, keyDown: Bool) throws {
		if let failure { throw failure }
		keyAttempts += 1
		if let keyFailure, keyFailureAt == nil || keyFailureAt == keyAttempts { throw keyFailure }
		keyed.append(Keyed(keyCode: keyCode, flags: flags, keyDown: keyDown))
		sequence.append(.key(keyCode, flags: flags, keyDown: keyDown))
	}

	public func postFlagsChanged(keyCode: UInt16, flags: CGEventFlags) throws {
		if let failure { throw failure }
		sequence.append(.flags(keyCode, flags))
	}
}
