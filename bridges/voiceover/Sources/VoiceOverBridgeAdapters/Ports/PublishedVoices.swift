// ROLE: adapter seam -- which voices this MACHINE publishes, by identifier.
//
// NOT A DOMAIN PORT: the domain asks "has the capture voice been published?" and
// does not know that the answer is a list from a speech framework.
//
// IMPLEMENTED BY: SystemPublishedVoices (a leaf) and FakePublishedVoices
// (Tests/Fakes). USED BY: PluginKitProviderLifecycle, which is the one place
// that decides what the list MEANS.
//
// SYSTEM-WIDE PUBLICATION IS NOT THE SAME QUESTION AS "DOES VOICEOVER OFFER IT",
// and the distance between them is exactly spec 0047's finding 6: the voice was
// absent from VoiceOver's own picker at the same moment this list reported 191
// voices with ours among them, with the extension registered and its process
// alive. Nothing observable from outside the reader distinguishes that from
// health, which is why `ProviderState.published` names a condition it cannot
// rule out rather than promoting itself to `selected`.
//
// IT IS ALSO WHERE THE PUBLISHED IDENTIFIER IS DISCOVERED RATHER THAN
// CONSTRUCTED. The system publishes our voice as the extension's bundle id
// followed by the one the audio unit declared, so the published string never
// equals what the unit said (spec 0041, A1) -- matching by SUFFIX against this
// list yields the identifier the system actually used, which is the one that has
// to be written into the preference.

public protocol PublishedVoices: AnyObject {
	func identifiers() -> [String]

	/// Ask the system to RE-READ the voices its speech providers offer -- 13.26.
	///
	/// ============================================================================
	/// A REGISTERED PROVIDER'S VOICES DO NOT APPEAR BECAUSE IT REGISTERED.
	/// ============================================================================
	///
	/// Something has to ask, and this is it. `CaptureProbe` has known that since
	/// 13.4 -- its `refresh` verb calls exactly this and its comment reads "the step
	/// the voice list will not happen without" -- and the HANDSHAKE did not, which
	/// cost 13.26's first live connect. The bridge registered the extension,
	/// restarted VoiceOver to publish the voice, and the voice was never published
	/// at all, so the reader came back up without it and the climb failed at
	/// `voiceSelection`. Measured 2026-09-02, transcript 22:31:35-37.
	///
	/// SO THE ORDER IS: register, REFRESH, wait for it to appear, and only THEN
	/// restart the reader. Restarting before the voice exists gives the reader a
	/// voice list that still does not contain it, which is a restart spent for
	/// nothing on somebody who is using their computer.
	///
	/// IT IS ASYNCHRONOUS. The call returns immediately and the system re-reads on
	/// its own schedule, so the caller polls -- which is `register()`'s existing
	/// shape and the same reason.
	func refresh()
}
