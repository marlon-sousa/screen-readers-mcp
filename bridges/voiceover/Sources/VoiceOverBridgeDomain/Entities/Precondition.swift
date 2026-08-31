// ROLE: entity -- the vocabulary of things this bridge can OBSERVE, cannot SET,
// and cannot work without. Pure.
//
// USED BY: the launcher's startup report, which prints each case's recovery when
// the machine is not in a state to run -- and, when it lands, the control
// dialog's preconditions row. BUILT BY: nobody -- it is an enumeration, and the
// state each case is in is read through a port.
//
// NAMING THE KIND IS WHAT STOPS A CONTROL SURFACE GROWING AD-HOC ROWS. A panel
// attracts one-off indicators, and each of them looks reasonable on its own; a
// row belongs here only if all three clauses hold, and a thing the bridge can
// FIX is not a precondition, it is work the bridge has not done yet.
//
// ONE TRUE INSTANCE TODAY, AND IT USED TO BE TWO. Spec 0046 named the capture
// voice's selection as the other -- until spec 0047's findings 16 and 17 showed
// that the voice is a single preference in the SYSTEM SPEECH domain and that
// writing it applies live, in both directions, with no reader restart. So the
// bridge SETS it (13.6 does, at every handshake) and the capture-voice row a
// control surface shows became a VIEW OF `ProviderState`: a state the bridge repairs, reported
// with its diagnosis, rather than a plea to a human. That is a better outcome
// than a second case here, and it is why this file says one and not two.
//
// THE PERMISSIONS ROW IS NOT HERE EITHER, for the opposite reason: an
// Accessibility or Automation grant is exactly a thing a human CAN be asked for,
// so it is a `Permission` with a request behind it (see PermissionBroker).
//
// IT MIRRORS `ReaderCondition` AND `Permission` DELIBERATELY -- summary,
// recovery, and one `described` rendering that keeps the two together. A
// diagnosis without its recovery is a complaint; a recovery without its
// diagnosis is a ritual.

public enum Precondition: String, Equatable, Sendable, CaseIterable {
	/// AppleScript control of VoiceOver, VoiceOver Utility > General. Without it
	/// every gesture, every liveness check and the VoiceOver-cursor route of
	/// `getFocusInfo` fail with `-1743`, and the bridge can do nothing about it.
	case readerScripting

	/// What is not possible without it, in one sentence.
	public var summary: String {
		switch self {
		case .readerScripting:
			return
				"AppleScript control of VoiceOver is not switched on, so this bridge cannot press "
				+ "the reader's own commands or ask it anything"
		}
	}

	/// What a human has to do about it -- and only a human can.
	///
	/// THE TWO LOCATIONS ARE NOT AN IMPLEMENTATION DETAIL HERE: naming the switch
	/// by its place in the reader's own settings is what a person can act on, and
	/// naming the files is what the next person to measure this needs. Both,
	/// because the audience is both.
	public var recovery: String {
		switch self {
		case .readerScripting:
			return
				"switch on 'Allow VoiceOver to be controlled with AppleScript' in VoiceOver Utility "
				+ "> General. No API sets it and this bridge cannot: it is recorded in the reader's "
				+ "own preferences (SCREnableAppleScript) and, on older systems, as the marker file "
				+ "/private/var/db/Accessibility/.VoiceOverAppleScriptEnabled"
		}
	}

	/// The one rendering, so the name and its recovery never travel apart.
	public var described: String {
		"\(rawValue): \(summary). Recovery: \(recovery)."
	}
}
