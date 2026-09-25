// ROLE: port -- whatever feeds the speech buffer with what the reader said.
// IMPLEMENTED BY: ContainerFileSpeechSource, over the LineTailer seam; FakeSpeechSource.
// BUILT BY: VoiceOverAdapterFactory.
// USED BY: the Hello handler starts it, and the Session's teardown stops it on every exit path.
// The feed file's absence is not a failure: the extension creates it the first time the reader speaks through the capture voice.
/// `emittedAt` is wall-clock epoch seconds stamped by the producer at emission; `0` means no instant was recorded.
public struct CapturedUtterance: Equatable, Sendable {
	public let text: String
	public let emittedAt: Double
	public let ssml: String
	public let voice: String

	public init(text: String, emittedAt: Double = 0, ssml: String = "", voice: String = "") {
		self.text = text
		self.emittedAt = emittedAt
		self.ssml = ssml
		self.voice = voice
	}
}

public protocol SpeechSource: AnyObject {
	/// Delivers on the source's own thread.
	func start(_ buffer: SpeechBuffer)

	/// Idempotent: teardown calls it on every path, including those where `start` was never reached.
	func stop()
}
