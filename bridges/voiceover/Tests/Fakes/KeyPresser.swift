// A hand-written stateful fake for the KeyPresser port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/KeyPresser.swift.
//
// It records every keystroke in the order it was asked to press them, because
// the ORDER is half of what `pressGesture` promises and a batch may mix
// keystrokes with the reader's own command names -- so a session test asserting
// that `command+l`, some typed text and `return` went out in that order needs
// this fake and `FakeGestureSender` to be readable side by side.
//
// It can be told to fail on a NAMED keystroke rather than on the next call, for
// the reason FakeGestureSender can: the interesting assertion about a mid-batch
// failure is that what came before it went out and what came after it did not.
// The key is the keystroke's canonical spelling, which is what the handler
// reports and what a test writes.
//
// AND NOTHING HERE POSTS AN EVENT. The real presser presses a chord into
// whatever window the developer has in front of them -- Command-W in a test run
// would close it -- so this is the only implementation any domain test may hold.

import VoiceOverBridgeDomain

public final class FakeKeyPresser: KeyPresser {
	public private(set) var pressed: [Keystroke] = []

	/// Canonical spelling to the error it should fail with. Anything not in the
	/// table succeeds, which is the ordinary case.
	public var failures: [String: KeyPressFailure] = [:]

	/// Called after each successful press, so a test can make speech arrive as a
	/// CONSEQUENCE of a chord -- the reader announces what the chord did to the
	/// focus -- rather than before the batch starts.
	public var onPress: ((Keystroke) -> Void)?

	public init() {}

	/// What was pressed, in the spelling a test writes.
	public var describedPresses: [String] {
		pressed.map(\.described)
	}

	public func press(_ keystroke: Keystroke) throws {
		pressed.append(keystroke)
		if let failure = failures[keystroke.described] { throw failure }
		onPress?(keystroke)
	}
}
