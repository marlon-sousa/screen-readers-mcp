// ROLE: port, implemented by MarkerFileCaptureModeSource: whether the bridge asks for silence, and in whose voice.
// Every adapter must answer `passThrough` when it cannot tell: rendering silence leaves the user unable to hear.

public struct CaptureDirective: Equatable, Sendable {
	public let silent: Bool

	/// nil means the bridge named no voice, as when no session is running, and VoiceChoice's other rules choose.
	public let preferredVoice: String?

	public init(silent: Bool, preferredVoice: String? = nil) {
		self.silent = silent
		self.preferredVoice = preferredVoice
	}

	public static let passThrough = CaptureDirective(silent: false, preferredVoice: nil)
}

public protocol CaptureModeSource {
	var directive: CaptureDirective { get }
}
