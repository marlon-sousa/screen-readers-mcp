// ROLE: port double -- what this machine says the VoiceOver modifier is bound
// to, answered from a value a test sets.
//
// STANDS IN FOR: ReaderModifierSetting. USED BY: the PressGesture handler tests,
// the session round-trip tests, and `fakeAdapterSet`.
//
// IT DEFAULTS TO `controlOption`, which is what an untouched Mac answers, so a
// test that does not care about the modifier reads as if the machine were
// ordinary. A test that DOES care sets `setting` and says so by doing it.
//
// IT COUNTS READS, because "read per call, never cached" is a decision spec 0052
// §3.2 makes and a decision worth being able to assert.

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
