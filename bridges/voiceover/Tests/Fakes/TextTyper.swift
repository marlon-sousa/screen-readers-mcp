// Hand-written stateful fake for the TextTyper port.
// Types nothing: the real typer posts events into the developer's front window.

import VoiceOverBridgeDomain

public final class FakeTextTyper: TextTyper {
	public private(set) var typed: [String] = []

	public var failure: TypingError?

	public var onType: ((String) -> Void)?

	public init() {}

	public func type(_ text: String) throws {
		typed.append(text)
		if let failure { throw failure }
		onType?(text)
	}
}
