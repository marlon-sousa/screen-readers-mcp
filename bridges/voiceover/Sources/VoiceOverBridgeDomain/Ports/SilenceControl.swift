// ROLE: port -- whether the human hears their own machine, and in whose voice
// they hear it when they do.
//
// IMPLEMENTED BY: MarkerFileSilenceControl (adapters), which writes the file the
// capture voice reads; FakeSilenceControl (Tests/Fakes).
// BUILT BY: VoiceOverAdapterFactory, one per session. USED BY: the Hello handler
// (which begins the lease and suppresses if the mode says so), the Session (which
// renews it, lifts it when the silence cap fires, and releases it at teardown)
// and the Ping handler (which reports it).
//
// SEPARATE FROM SpeechSource BECAUSE CAPTURE IS IDENTICAL IN BOTH MODES HERE.
// Only RENDERING differs, and the extension does the rendering: the same feed,
// the same indices and the same timestamps arrive either way. That is what makes
// a lift cheap on this route -- protocol.md §6.1's table is literally true here,
// with words stopping and evidence continuing.
//
// SILENCE IS A LEASE, NOT A STATE, AND THAT IS THE WHOLE DESIGN (spec 0046).
// protocol.md §6 asks a bridge to arrange its interception so that LOSING THE
// BRIDGE ITSELF lifts it. NVDA gives that free -- it holds extension-point
// handlers weakly, so killing the add-on drops the speech filter with it. Here
// the interception is a file on disk read by a process the system owns, which
// would go on reading it forever. So the marker EXPIRES, `renew()` is what keeps
// it alive, and a bridge that is SIGKILLed un-mutes the machine by doing nothing
// at all.
//
// `release()` STAYS ANYWAY, and nothing may depend on it. It makes the ordinary
// teardown immediate rather than up-to-a-lease late, which is worth having; it
// is not the guarantee. The guarantee is the expiry, because a `defer` does not
// run at SIGKILL, at a panic or at a power cut -- which are exactly the cases
// hard invariant 3 is about.

public protocol SilenceControl: AnyObject {
	/// Open the channel for a session, in PASS-THROUGH, naming the voice the user
	/// chose for themselves.
	///
	/// The voice is on this channel and not on another one because the bridge
	/// holds it anyway -- it is what teardown restores -- and pass-through that
	/// re-speaks in the user's own voice is acoustically invisible rather than a
	/// substitute nobody asked for (spec 0046, "Rule 0"). Nil means the bridge
	/// could not read one, or read one that was OURS, in which case the extension
	/// chooses by its own rules rather than assuming.
	func begin(preferredVoice: String?) throws

	/// Withhold the reader's speech from the human, from its next utterance on.
	func suppress() throws

	/// Let the human hear their machine again. Capture is unaffected: the agent
	/// keeps reading the same entries, at the same indices, with the same stamps.
	func passThrough() throws

	/// Re-arm the lease. Cheap, idempotent, and called far more often than
	/// anything else on this port -- so it does not throw: a failed renewal
	/// expires the lease, which is the safe direction and needs no handling.
	func renew()

	/// Whether words are being withheld right now. What `ping` reports.
	var isSuppressing: Bool { get }

	/// Drop the channel. The ordinary case's immediate lift, and never the
	/// guarantee -- see the header.
	func release()
}
