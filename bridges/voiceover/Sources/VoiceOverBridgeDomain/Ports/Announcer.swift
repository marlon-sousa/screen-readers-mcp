// ROLE: port -- the bridge's channel TO the human sitting at the reader.
//
// IMPLEMENTED BY: SynthesizerAnnouncer (adapters), over the SpeechOut seam;
// FakeAnnouncer (Tests/Fakes).
// BUILT BY: Wiring, once per process, and handed to the session in the
// AdapterSet. USED BY: the Announce controller, and by `HumanWarning` on behalf
// of `pressGesture` and `typeText`.
//
// ============================================================================
// IT SPEAKS WITH THE BRIDGE'S OWN SYNTHESIZER, OUTSIDE VOICEOVER ENTIRELY.
// ============================================================================
//
// That is the whole reason `announce` is audible in a SILENT session, which is
// the one mode where it is the human's only channel: on this platform the
// suppression is rendered inside the capture voice, so anything spoken through
// the reader is exactly what the person cannot hear. Going around the reader is
// a cleaner bypass than NVDA's -- there, `announce` reaches the real synth that
// NVDA still has loaded, and the claim depends on the interception being a
// filter rather than a mute -- and it is why `pressGesture`'s and `typeText`'s
// `announce` field can be honoured here at all.
//
// THE ONE CAVEAT IS OUR OWN VOICE, and it belongs to the adapter rather than to
// this contract: a bridge that announced through the capture voice would be
// silence talking to itself, because that voice reads the marker and renders
// nothing while a silent session holds it. `SynthesizerAnnouncer` excludes it by
// identifier suffix, the same rule the voice store already matches ours by.
//
// IT THROWS, AND THE SESSION DOES NOT SWALLOW IT. A cue is a courtesy and never
// worth a session (see SessionSignals); an `announce` is a PROMISE ABOUT A
// HUMAN'S EARS that the agent asked for and is waiting on an answer to, so a
// failure to speak is reported as a failed command rather than noted and hidden.
public protocol Announcer: AnyObject {
	/// Say `text` to the human at the machine, now.
	///
	/// The bridge acknowledges that it SPOKE, never that anyone listened
	/// (protocol.md §5). Whitespace-only text is the caller's business: the
	/// controllers treat it as "say nothing" before they ever get here.
	func announce(_ text: String) throws
}

/// Why nothing could be said out loud.
///
/// Its own type rather than the command layer's `CommandError`, because a port
/// may not depend on a controller. The handlers translate it.
public struct AnnouncerError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}
