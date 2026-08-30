// ROLE: port -- AUDIO OUTPUT. Given an utterance and a voice, produce audio into
// the ring and say when it is done.
//
// Implemented by AVFoundationSynthesizer; held by CaptureController, which calls
// it only when silence is not in force. Faked in CaptureControllerTests, which is
// how the controller is tested with no audio device and no VoiceOver.
//
// WHY THE RING IS A PARAMETER rather than something the port returns: the
// consumer of these samples is a render block on the audio thread, which cannot
// wait on anything and cannot allocate. The ring is the entity that meets both
// constraints, the controller owns it, and the synthesizer is a producer into it.
//
// NOTHING HERE MENTIONS AVFoundation. That is the point of the port: the domain
// says "re-speak this utterance in that voice", and which framework does it is
// the adapter's business.

/// What the last utterance's re-synthesis cost, read when it ends.
///
/// This is the instrument spec 0041 used to tell "our buffering is wrong" from
/// "the thing producing audio stopped for ten seconds", and it is kept because
/// the live checklist still needs it: an utterance that sounded wrong is
/// diagnosable from the emitted numbers instead of from a second live round.
public struct SynthesisStatistics: Equatable, Sendable {
	/// How long the producer was waited for before playback could start.
	public let prebufferMilliseconds: Int
	/// Buffers the synthesizer handed back.
	public let callbackCount: Int
	/// Time from the request to the first buffer, or -1 if none arrived.
	public let firstCallbackMilliseconds: Int
	/// The longest silence between two buffers -- a starved producer's signature.
	public let maxGapMilliseconds: Int
	/// Frames appended to the ring.
	public let totalFrames: Int
	/// Wall time from the request to the last buffer. Divided into the audio
	/// produced, this is the PRODUCTION RATE -- the number that decided the
	/// offline-render argument (spec 0041, C4: 24.4x realtime).
	public let spanMilliseconds: Int
	/// What the chosen voice actually produced, which is not knowable in advance.
	/// `nil` until the first buffer arrives.
	public let sourceSampleRate: Double?
	public let sourceChannels: Int?
	/// Whether every buffer had to go through a format converter.
	public let converted: Bool?

	public init(
		prebufferMilliseconds: Int,
		callbackCount: Int,
		firstCallbackMilliseconds: Int,
		maxGapMilliseconds: Int,
		totalFrames: Int,
		spanMilliseconds: Int,
		sourceSampleRate: Double?,
		sourceChannels: Int?,
		converted: Bool?
	) {
		self.prebufferMilliseconds = prebufferMilliseconds
		self.callbackCount = callbackCount
		self.firstCallbackMilliseconds = firstCallbackMilliseconds
		self.maxGapMilliseconds = maxGapMilliseconds
		self.totalFrames = totalFrames
		self.spanMilliseconds = spanMilliseconds
		self.sourceSampleRate = sourceSampleRate
		self.sourceChannels = sourceChannels
		self.converted = converted
	}
}

public protocol Synthesizer: AnyObject {
	/// Starts re-synthesis of `utterance` in `voice`, appending to `ring`.
	///
	/// May block briefly waiting for the first samples -- the render block has no
	/// way to say "not ready yet", so somebody has to wait, and here is the thread
	/// that may (spec 0041, C4).
	func speak(_ utterance: Utterance, as voice: AvailableVoice, into ring: AudioRing)

	/// Stops the current utterance. Ordinary, not exceptional: VoiceOver cancels
	/// before every new utterance.
	func cancel()

	func statistics() -> SynthesisStatistics
}
