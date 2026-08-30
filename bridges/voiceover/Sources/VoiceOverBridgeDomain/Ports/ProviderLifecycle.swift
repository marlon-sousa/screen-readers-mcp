// ROLE: port -- where the capture voice has got to, and pointing the reader at
// it.
//
// ELEMENT 2 OF THE FIVE, NAMED RATHER THAN HIDDEN INSIDE A HEALTH CHECK (spec
// 0046, part 3). Detection and selection are one component because they are one
// state machine, and the dialog's capture-voice row (13.10) is a view of it.
//
// IMPLEMENTED BY: PluginKitProviderLifecycle (adapters); FakeProviderLifecycle
// (Tests/Fakes).
// BUILT BY: VoiceOverAdapterFactory. USED BY: the Hello handler, which reads the
// user's own voice, records it, selects ours and refuses a silent session it
// cannot keep; the Session, which puts the user's voice back on every teardown
// path; and the two waiting speech handlers, which turn an empty read-back into
// a named condition rather than a shrug.
//
// SELECTING THE VOICE IS THE BRIDGE'S JOB, NOT A HUMAN'S, and that became true
// only on 2026-08-29: spec 0047 findings 16-17 found the reader's selected voice
// IS a preference -- in the SYSTEM SPEECH domain, not VoiceOver's own -- settable
// live, in both directions, with no reader restart, no UI and no Accessibility
// grant. Everything before that finding assumed a human in VoiceOver Utility.
//
// WHAT IS NOT HERE, AND WHY. `register()` / `unregister()` are named in spec
// 0046's 13.6 table and are deliberately absent: re-registration only takes
// effect after the reader is RESTARTED (spec 0047, finding 6), and restarting a
// blind person's screen reader is not something a handshake may decide. They
// arrive with the control dialog (13.10), beside the row that a human drives --
// which is the same rule as "a capability is announced by the entry that
// implements it", applied to a port.

/// The voice VoiceOver is currently set to speak with.
///
/// `isCaptureVoice` is answered by the adapter, which is the only side that
/// knows what our published identifier is -- and it answers by SUFFIX, because
/// the system publishes our voice as the extension's bundle id followed by ours
/// and it therefore never equals what the audio unit declared (spec 0041, A1).
///
/// The distinction is load-bearing rather than informational: a previous session
/// that died without restoring leaves OUR voice as "the user's own", and a bridge
/// that recorded it as such would restore our own voice at teardown and hand the
/// extension itself as the pass-through voice -- which is infinite recursion.
public struct SelectedVoice: Equatable, Sendable {
	public let identifier: String
	public let isCaptureVoice: Bool

	public init(identifier: String, isCaptureVoice: Bool) {
		self.identifier = identifier
		self.isCaptureVoice = isCaptureVoice
	}
}

/// The reader edge refusing, or failing, to do something with the voice.
///
/// Its own type rather than the command layer's `CommandError`, because a port
/// may not depend on a controller; the handlers translate it.
public struct ProviderError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol ProviderLifecycle: AnyObject {
	/// How far along the capture voice is. NEVER THROWS: every question this
	/// cannot answer is itself a state, and an error would collapse five
	/// different diagnoses into one.
	func state() -> ProviderState

	/// What the reader is set to speak with, or nil if the store cannot be read.
	func selectedVoice() -> SelectedVoice?

	/// Point the reader at the capture voice, and confirm it took.
	///
	/// CONFIRMING IS PART OF THE CONTRACT. A value written with the wrong plist
	/// TYPE is silently rejected and then overwritten by VoiceOver's own choice,
	/// so the evidence of the write is gone before anyone looks (spec 0047,
	/// finding 17). An implementation that wrote and returned would report success
	/// for the one failure mode this route actually has.
	func selectCaptureVoice() throws

	/// Put back what the user had. Called on every teardown path.
	func restoreVoice(_ identifier: String) throws
}
