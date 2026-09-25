// ROLE: port that re-speaks an utterance in a voice, into the ring.
// IMPLEMENTED BY: AVFoundationSynthesizer.

public struct SynthesisStatistics: Equatable, Sendable {
	public let prebufferMilliseconds: Int
	public let callbackCount: Int
	/// -1 if no buffer arrived.
	public let firstCallbackMilliseconds: Int
	public let maxGapMilliseconds: Int
	public let totalFrames: Int
	public let spanMilliseconds: Int
	/// nil until the first buffer arrives.
	public let sourceSampleRate: Double?
	public let sourceChannels: Int?
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
	/// May block briefly waiting for the first samples: the render block cannot say "not ready yet".
	func speak(_ utterance: Utterance, as voice: AvailableVoice, into ring: AudioRing)

	func cancel()

	func statistics() -> SynthesisStatistics
}
