// ROLE: entity -- one outstanding question to the human: its ticket, its window, and whether asking it cost the session its silence.
// BUILT BY: the AskUser controller, once per `askUser`, and hung on the SessionContext.
// USED BY: WaitForUserReply for expiry, and the Session for the silence cap and teardown.
public final class UserPrompt {
	public static let window: Double = 300.0

	public let ticket: PromptId
	public let prompt: String
	private let openedAt: Double
	private let lifetime: Double

	/// Whether opening this window lifted a silent session's suppression, which closing it must put back.
	public var suspendedSilence = false

	public init(
		ticket: PromptId,
		prompt: String,
		now: Double,
		lifetime: Double = UserPrompt.window
	) {
		self.ticket = ticket
		self.prompt = prompt
		self.openedAt = now
		self.lifetime = lifetime
	}

	public func isExpired(_ now: Double) -> Bool {
		now - openedAt >= lifetime
	}

	public func remaining(_ now: Double) -> Double {
		max(0, lifetime - (now - openedAt))
	}
}
