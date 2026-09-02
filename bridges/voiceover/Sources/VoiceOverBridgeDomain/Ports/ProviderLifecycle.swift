// ROLE: port -- where the capture voice has got to, and pointing the reader at
// it.
//
// ELEMENT 2 OF THE FIVE, NAMED RATHER THAN HIDDEN INSIDE A HEALTH CHECK (spec
// 0046, part 3). Detection and selection are one component because they are one
// state machine, and a control surface's capture-voice row is a view of it.
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
// REGISTERING IS THE BRIDGE'S JOB TOO, SINCE 13.20 -- AND THIS PARAGRAPH USED TO
// SAY THE OPPOSITE. It read, until spec 0050:
//
//   "`register()` / `unregister()` are named in spec 0046's 13.6 table and are
//    deliberately absent: re-registration only takes effect after the reader is
//    RESTARTED (spec 0047, finding 6), and restarting a blind person's screen
//    reader is not something a handshake may decide."
//
// The argument is right about the RESTART and was over-applied to the
// REGISTRATION. Registering is silent: two subprocesses, nothing a running
// reader can see, no dialog and no grant. Only its EFFECT needs a restart. So
// `register()` is here and the restart is still not: the handshake climbs as far
// as it can and NAMES the one action it may not take (see ReaderCondition).
//
// What it cost to leave it out is the reason 13.20 exists: `poe build` deletes
// and reassembles the bundle, the system forgets the extension, and every
// session afterwards answered `speech: []` -- indistinguishable from "the reader
// said nothing". An hour of a live checklist, on 2026-08-31, with the bridge
// printing `providerNotRunning` at startup the whole time.
//
// THERE IS NO `unregister()`, AND THERE MUST NOT BE. The symmetry is tempting
// and the temptation is exactly the bug: SESSION state is restored at teardown
// -- the voice SELECTION, hard invariant 3, `restoreVoice` below -- and MACHINE
// state is not. Undoing the registration would put the next session back in the
// state this entry exists to repair, and the bridge's accept loop is serial
// today but will not always be: one client's disconnect must never deregister
// the voice out from under another. A human who really wants it gone runs
// `pluginkit -r` on the .appex, which this bridge's README documents.

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

	/// Register the capture voice's extension with the system, and confirm it
	/// took. ADDED AT 13.20; called by the handshake when `state()` is
	/// `.notRegistered`, and by nothing at teardown -- see the header.
	///
	/// CONFIRMING MEANS POLLING HERE, not reading an exit status. Measured
	/// 2026-08-31: `pluginkit -a` hands the work to `pkd` and returns, so an
	/// immediate re-read reports failure on a registration that worked. A false
	/// alarm is worse than no check, because it sends a human to redo something
	/// that is already done.
	///
	/// IT DOES NOT PROMISE THE VOICE IS USABLE, and cannot: the system publishes
	/// a newly registered voice only after VoiceOver RESTARTS (spec 0047, finding
	/// 6). This gets the ladder to `registered`; whoever needs `published` needs
	/// a human. That is the honest limit and the callers say so by name.
	func register() throws

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
