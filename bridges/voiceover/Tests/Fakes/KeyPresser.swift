// Hand-written stateful fake for the KeyPresser port.
// Posts no event: the real presser types into the developer's front window, so domain tests hold only this fake.

import VoiceOverBridgeDomain

public final class FakeKeyPresser: KeyPresser {
	public private(set) var pressed: [Keystroke] = []

	public var failures: [String: KeyPressFailure] = [:]

	public var onPress: ((Keystroke) -> Void)?

	public init() {}

	public var describedPresses: [String] {
		pressed.map(\.described)
	}

	public func press(_ keystroke: Keystroke) throws {
		pressed.append(keystroke)
		if let failure = failures[keystroke.described] { throw failure }
		onPress?(keystroke)
	}
}
