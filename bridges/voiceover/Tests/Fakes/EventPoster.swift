// No test may post a real event: the real poster types into whatever window is in front of the developer.

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

	/// `characters` matters: this reader matches on the character, and a keycode-built CGEvent carries the unshifted one whatever flags are set.
	public struct Keyed: Equatable {
		public let keyCode: UInt16
		public let flags: CGEventFlags
		public let characters: String?
		public let keyDown: Bool

		public init(keyCode: UInt16, flags: CGEventFlags, characters: String?, keyDown: Bool) {
			self.keyCode = keyCode
			self.flags = flags
			self.characters = characters
			self.keyDown = keyDown
		}
	}

	public enum Event: Equatable {
		case unicode(String, keyDown: Bool)
		case key(UInt16, flags: CGEventFlags, characters: String?, keyDown: Bool)
		case flags(UInt16, CGEventFlags)
	}

	public private(set) var posted: [Posted] = []
	public private(set) var keyed: [Keyed] = []
	public private(set) var sequence: [Event] = []

	public var flagTransitions: [CGEventFlags] {
		sequence.compactMap { if case .flags(_, let f) = $0 { return f } else { return nil } }
	}

	public var failure: EventPostingFailure?

	public init() {}

	public var typedText: String {
		posted.filter(\.keyDown).map(\.unicode).joined()
	}

	/// Fails only the key events, so a test can show the modifier release still happens when the press failed.
	public var keyFailure: EventPostingFailure?

	/// The 1-based key event `keyFailure` applies to; nil means every one.
	public var keyFailureAt: Int?

	private var keyAttempts = 0

	/// Key down only: a hook on every event of a press would answer one keystroke four times.
	public var onKeyDown: ((Keyed) -> Void)?

	/// Failure injections and `keyAttempts` are not reset, so this cannot disarm a test's own setup.
	public func forgetRecording() {
		posted = []
		keyed = []
		sequence = []
	}

	public func post(unicode: String, keyDown: Bool) throws {
		if let failure { throw failure }
		posted.append(Posted(unicode: unicode, keyDown: keyDown))
		sequence.append(.unicode(unicode, keyDown: keyDown))
	}

	public func post(
		keyCode: UInt16, flags: CGEventFlags, characters: String?, keyDown: Bool
	) throws {
		if let failure { throw failure }
		keyAttempts += 1
		if let keyFailure, keyFailureAt == nil || keyFailureAt == keyAttempts { throw keyFailure }
		let event = Keyed(keyCode: keyCode, flags: flags, characters: characters, keyDown: keyDown)
		keyed.append(event)
		sequence.append(.key(keyCode, flags: flags, characters: characters, keyDown: keyDown))
		if keyDown { onKeyDown?(event) }
	}

	public func postFlagsChanged(keyCode: UInt16, flags: CGEventFlags) throws {
		if let failure { throw failure }
		sequence.append(.flags(keyCode, flags))
	}
}
