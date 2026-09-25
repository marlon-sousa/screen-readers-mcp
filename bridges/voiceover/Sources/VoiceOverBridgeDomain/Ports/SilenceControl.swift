// ROLE: port -- whether the human hears their own machine, and in whose voice.
// IMPLEMENTED BY: MarkerFileSilenceControl, which writes the file the capture voice reads; FakeSilenceControl.
// BUILT BY: VoiceOverAdapterFactory, one per session.
// USED BY: the Hello handler, the Session and the Ping handler.
// Silence is a lease: the marker expires unless `renew()` keeps it alive, so a killed bridge un-mutes the machine by doing nothing.
// `release()` only makes an ordinary teardown immediate; nothing may depend on it, because a `defer` does not run at SIGKILL.

public protocol SilenceControl: AnyObject {
	/// Nil means no voice of the user's could be read, or it was ours, and the extension then chooses by its own rules.
	func begin(preferredVoice: String?) throws

	func suppress() throws

	func passThrough() throws

	/// Does not throw: a failed renewal expires the lease, which is the safe direction.
	func renew()

	var isSuppressing: Bool { get }

	func release()
}
