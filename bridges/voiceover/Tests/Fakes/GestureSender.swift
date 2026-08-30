// A hand-written stateful fake for the GestureSender port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/GestureSender.swift.
//
// It records every command in the order it was asked to press them, because the
// ORDER is half of what `pressGesture` promises -- "press the given ids in
// order, blocking until each is processed" -- and a double that only counted
// calls could not tell a batch that ran backwards from one that did not.
//
// It can be told to fail on a NAMED command rather than on the next call, which
// is what makes the mid-batch abort testable: the interesting assertion is that
// the commands before the failing one went out and the ones after it did not.

import VoiceOverBridgeDomain

public final class FakeGestureSender: GestureSender {
	public private(set) var pressed: [String] = []

	/// Command name to the error it should fail with. Anything not in the table
	/// succeeds, which is the ordinary case.
	public var failures: [String: GestureError] = [:]

	/// Called after each successful press, so a test can make speech arrive as a
	/// CONSEQUENCE of a command rather than before the batch starts. Without it
	/// the grace window can only be tested against a buffer that was already
	/// full, which is the one arrangement that cannot go wrong.
	public var onPress: ((String) -> Void)?

	public init() {}

	public func press(_ command: String) throws {
		pressed.append(command)
		if let failure = failures[command] { throw failure }
		onPress?(command)
	}
}
