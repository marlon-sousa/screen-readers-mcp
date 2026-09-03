// ROLE: port -- what has the person at this machine bound their VoiceOver
// modifier to?
//
// IMPLEMENTED BY: VoiceOverPrefsModifierSetting (adapters), over the PlistReader
// seam; FakeReaderModifierSetting (Tests/Fakes).
// BUILT BY: Wiring, once per process, and handed to the session in the
// AdapterSet. USED BY: the PressGesture handler, which asks it once per call and
// hands the answer to CommandVocabulary.
//
// ============================================================================
// IT EXISTS BECAUSE A BLIND USER PRESSES VO-M, AND SO MUST WE -- 13.25.
// ============================================================================
//
// A VoiceOver user reaches the menu bar by pressing VO-M. Until this entry this
// bridge dispatched the command name `go to menu bar` instead, which is a
// different path through the machine: a keystroke goes out through the window
// server and past the focused application, and a command name is dispatched
// INSIDE the reader and never passes the application at all. So an application
// that swallows or reinterprets VO-M is invisible to the route the guidance
// recommended, which is the defect class this tool exists to find. Spec 0052 §1.
//
// `vo` IS THE COUNTERPART OF LANE 1's `nvda`, AND THAT IS WHY THIS IS A PORT
// RATHER THAN A CONSTANT. NVDA's gesture ids carry `NVDA+f7`, and NVDA resolves
// that symbol against its own configuration -- Insert, Extended Insert or Caps
// Lock, whichever the person chose. This bridge posts the events itself, so it
// has to do the resolving, so it has to READ the machine. The refusal 13.19 wrote
// down ("`VO` is whatever the person has bound it to, so this bridge will not
// guess") was right about the hazard and wrong about the remedy: the answer is
// written down, and reading it is what this port does.
//
// THREE ANSWERS AND AN `unknown`, WHICH IS `ReaderScriptingSetting`'s SHAPE FOR
// `ReaderScriptingSetting`'s REASON. VoiceOver records only DEVIATIONS from its
// defaults, so "readable and not mentioned" IS Control-Option; and a file this
// process could not read at all is not a machine at its default, it is one this
// bridge does not know. Only one of those two justifies pressing keys at
// somebody's screen reader.

/// What the machine says the VoiceOver modifier is.
public enum ModifierSetting: String, Equatable, Sendable, CaseIterable {
	/// Control-Option, which is what VoiceOver ships with. Also the answer when
	/// the preference is readable and says nothing: the reader records deviations
	/// only.
	case controlOption

	/// Caps Lock alone. `control+option` is then NOT the modifier on this machine,
	/// which is why the entity refuses `vo` rather than pressing two keys that
	/// mean nothing here.
	case capsLock

	/// Either the two keys or Caps Lock. `control+option` is a correct answer
	/// here, so `vo` resolves exactly as it does at the default.
	case controlOptionOrCapsLock

	/// The preference could not be read, or holds a value this bridge does not
	/// know. Not a fault, and NOT a default.
	case unknown
}

public protocol ReaderModifierSetting: AnyObject {
	/// Read the setting now.
	///
	/// ASKED PER CALL, NEVER CACHED FOR A SESSION -- which is the same rule
	/// `CurrentKeyboardLayout` follows for the keyboard layout, for the same
	/// reason: somebody who changes it mid-session gets the right keys on the very
	/// next press, and there is no notification observer to register, forget to
	/// remove, or receive on the wrong thread. It reads one property list and
	/// changes nothing.
	func modifier() -> ModifierSetting
}
