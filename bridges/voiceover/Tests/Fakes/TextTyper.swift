// A hand-written stateful fake for the TextTyper port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/TextTyper.swift.
//
// IT EXISTS SO THAT NO TEST EVER TYPES ANYTHING. The real typer posts events
// into whatever window the developer has in front of them at that moment, which
// is a worse accident than the one `Support/ReaderEdge.swift` was written to
// prevent: a failed test would leave text in somebody's document.
//
// It records the strings it was handed, whole and in order, because a caller's
// job is to hand over exactly what arrived on the wire -- untouched, control
// characters and all (protocol.md §5). CHUNKING IS NOT VISIBLE HERE and must not
// be: it is `AccessibilityTextTyper`'s decision, tested against a fake
// EventPoster one layer down.

import VoiceOverBridgeDomain

public final class FakeTextTyper: TextTyper {
	public private(set) var typed: [String] = []

	/// Set to make the next call fail, which is how the handler's error path is
	/// exercised without a machine that can fail.
	public var failure: TypingError?

	/// Called after each successful call, so a test can make speech arrive as a
	/// CONSEQUENCE of typing rather than before it -- the same reason
	/// FakeGestureSender has one.
	public var onType: ((String) -> Void)?

	public init() {}

	public func type(_ text: String) throws {
		typed.append(text)
		if let failure { throw failure }
		onType?(text)
	}
}
