// ROLE: port -- what the person at this machine has bound their VoiceOver modifier to.
// IMPLEMENTED BY: VoiceOverPrefsModifierSetting, over the PlistReader seam; FakeReaderModifierSetting.
// BUILT BY: Wiring, once per process, and handed to the session in the AdapterSet.
// USED BY: the PressGesture handler, which hands the answer to CommandVocabulary.
// VoiceOver records only deviations, so a readable preference that says nothing is Control-Option, while an unreadable one is `unknown`.

public enum ModifierSetting: String, Equatable, Sendable, CaseIterable {
	case controlOption

	case capsLock

	case controlOptionOrCapsLock

	/// Unreadable or unrecognised: not a fault, and not a default.
	case unknown
}

public protocol ReaderModifierSetting: AnyObject {
	/// Read per call, never cached, so a mid-session change applies on the next press.
	func modifier() -> ModifierSetting
}
