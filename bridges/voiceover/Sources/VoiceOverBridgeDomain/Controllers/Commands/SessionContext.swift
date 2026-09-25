// ROLE: parameter object, the per-session bundle every handler is handed plus one lifecycle
// capability.
// BUILT BY: the Session, once per session.
// POPULATED BY: the Hello handler, the only command that fills the fields a handshake creates.

import ScreenReaderWire

public final class SessionContext {
	public let clock: Clock
	public let transcript: Transcript

	/// Whether a human is expected at this machine; read from the bridge's configuration, never the wire.
	public let attended: Bool

	public var mode: CaptureMode?

	/// Set before anything is started, so teardown can stop what was started if the handshake throws.
	public var adapters: AdapterSet?

	public var speech: SpeechBuffer?

	/// The user's own voice, restored at teardown. Nil means nothing to restore: the store could not be
	/// read, or it held our own voice, which restoring would make the extension its own pass-through.
	/// Set before the voice is changed, so a failed handshake still leaves teardown holding it.
	public var previousVoice: String?

	/// The silence cap of a silent session; nil in a live session and on an unattended machine.
	public var silenceCap: SilenceCap?

	public var outstandingPrompt: UserPrompt?

	public let silenceCapPolicy: SilenceCapPolicy

	/// Recorded as received and never validated: an unfamiliar persona must not refuse a session.
	public var persona: String = ""

	private let closeSession: (TeardownReason) -> Void

	public init(
		clock: Clock,
		transcript: Transcript,
		attended: Bool,
		silenceCapPolicy: SilenceCapPolicy = .attendedDefault,
		close: @escaping (TeardownReason) -> Void
	) {
		self.clock = clock
		self.transcript = transcript
		self.attended = attended
		self.silenceCapPolicy = silenceCapPolicy
		self.closeSession = close
	}

	/// Throws rather than traps: the case is unreachable after `hello`, and a wrong one should cost one
	/// command, not the user's screen reader.
	public func speechBuffer() throws -> SpeechBuffer {
		guard let speech else {
			throw CommandError("the speech buffer was read before `hello` installed it")
		}
		return speech
	}

	/// Call only for sounds that reach the human past the suppression, and only after the sound was made.
	public func humanHeard() {
		silenceCap?.heard(clock.monotonic())
	}

	/// Cooperative: the loop honours it at its next wakeup, so `bye` is acknowledged before the
	/// connection closes.
	public func close(_ reason: TeardownReason) {
		closeSession(reason)
	}
}
