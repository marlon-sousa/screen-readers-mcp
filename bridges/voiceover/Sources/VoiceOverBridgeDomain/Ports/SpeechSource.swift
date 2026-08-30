// ROLE: port -- whatever feeds the speech buffer with what the reader said.
//
// IMPLEMENTED BY: ContainerFileSpeechSource (adapters), over the LineTailer
// seam; FakeSpeechSource (Tests/Fakes).
// BUILT BY: VoiceOverAdapterFactory, which is the only place that knows what a
// capture mode means. STARTED BY: the Hello handler, once the mode is known and
// after the adapter set is on the context. STOPPED BY: the Session's teardown,
// on every exit path.
// OWNS: `CapturedUtterance`, this port's DTO, in this file per the repo's rule
// that a port's types live with the port.
//
// THE SESSION NEVER LEARNS HOW CAPTURE HAPPENS. Here it is a JSON-lines file in
// a sandboxed extension's container -- the only door out of a speech provider,
// since one holding `com.apple.security.network.client` is silently skipped by
// macOS (spec 0041, B1) -- and the domain is entitled to know none of that.
//
// NEITHER METHOD THROWS, AND BOTH HALVES OF THAT ARE DELIBERATE (the lane's rule
// is that a port which can fail says so in its type):
//
//   * `start` cannot fail because THE FILE'S ABSENCE IS NOT A FAILURE. The
//     extension creates it the first time the reader speaks through our voice,
//     which may be after this session began; a source that threw on a file that
//     is not there yet would refuse a handshake over a race. A file that never
//     appears is a reader condition -- the capture voice not selected, or the
//     provider not running -- and 13.6 is where those are detected and REPORTED
//     BY NAME rather than surfacing as an exception here or as an empty read.
//   * `stop` cannot fail because teardown calls it, and a teardown step that
//     could throw is one that could skip the steps after it.

/// One thing the reader said, as the bridge captured it.
///
/// `emittedAt` is WALL-CLOCK EPOCH SECONDS taken by the producer at the moment
/// the utterance was emitted (spec 0028) -- not the moment the bridge read the
/// line, which is later by however long the feed's tail latency is. On this
/// route the extension stamps every line as it writes it, so the number survives
/// the file handoff intact. `0` means no instant was recorded, and a controller
/// renders that as an empty string rather than as 1970.
///
/// `ssml` is kept verbatim beside the words because it carries PROSODIC MEANING
/// the words do not -- the outer rate is the user's speech rate, and an inner
/// pitch is the reader lowering its voice for a column header. Nothing reads it
/// yet; it is carried rather than discarded because it cannot be recovered later.
public struct CapturedUtterance: Equatable, Sendable {
	public let text: String
	public let emittedAt: Double
	public let ssml: String
	/// The voice the reader asked for -- ours, when the capture voice is the one
	/// selected. Carried for the transcript and for 13.6's named conditions.
	public let voice: String

	public init(text: String, emittedAt: Double = 0, ssml: String = "", voice: String = "") {
		self.text = text
		self.emittedAt = emittedAt
		self.ssml = ssml
		self.voice = voice
	}
}

public protocol SpeechSource: AnyObject {
	/// Begin feeding captured utterances into `buffer`.
	///
	/// Delivery is asynchronous and on the source's own thread: the session
	/// thread spends its life blocked in `MessageChannel.read`, so nothing would
	/// fill the buffer if capture waited to be asked. The buffer is what makes
	/// that safe -- it is the one entity in this domain with a lock.
	func start(_ buffer: SpeechBuffer)

	/// Stop capturing. Idempotent: teardown calls it on every path, including
	/// paths where `start` was never reached.
	func stop()
}
