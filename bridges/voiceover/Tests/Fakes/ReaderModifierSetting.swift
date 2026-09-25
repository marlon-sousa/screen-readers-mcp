// ROLE: port double for ReaderModifierSetting, answering a value a test sets.
// USED BY: the PressGesture handler tests, the session round-trip tests and `fakeAdapterSet`.

import VoiceOverBridgeDomain

public final class FakeReaderModifierSetting: ReaderModifierSetting {
	public var setting: ModifierSetting
	public private(set) var reads = 0

	public init(_ setting: ModifierSetting = .controlOption) {
		self.setting = setting
	}

	public func modifier() -> ModifierSetting {
		reads += 1
		return setting
	}
}
