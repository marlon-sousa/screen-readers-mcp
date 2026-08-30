// A hand-written stateful fake for the EventPoster adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/EventPoster.swift.
//
// IT RECORDS THE PAYLOAD AND WHICH HALF OF THE KEYSTROKE IT WAS, because both
// are decisions the layer above makes: how the text was cut into payloads, and
// that every chunk goes out as a down and then an up. A double that only
// collected the text would pass a typer that sent key-downs and no key-ups.
//
// AND NO TEST POSTS A REAL EVENT. The real poster types into whatever window is
// in front of the developer, so this is the only implementation any test may
// ever hold.

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

	public private(set) var posted: [Posted] = []

	/// Set to make every call fail, which is how the typer's translation of a
	/// posting failure is exercised.
	public var failure: EventPostingFailure?

	public init() {}

	/// What was typed, reassembled -- the key-downs only, so the reassembly is
	/// not doubled by the key-ups.
	public var typedText: String {
		posted.filter(\.keyDown).map(\.unicode).joined()
	}

	public func post(unicode: String, keyDown: Bool) throws {
		if let failure { throw failure }
		posted.append(Posted(unicode: unicode, keyDown: keyDown))
	}
}
