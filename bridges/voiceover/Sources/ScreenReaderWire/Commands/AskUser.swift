// ROLE: entity -- `askUser`'s params and result.
//
// Pure. The result is a TICKET rather than an answer, and that is the whole
// design: asking must not block the session's dispatch loop, so the reply is
// collected later by `waitForUserReply` against this ticket. A bridge that
// waited here would stop answering pings while a human thought.

public struct AskUserParams: Codable, Equatable, Sendable {
	public var prompt: String

	public init(prompt: String) {
		self.prompt = prompt
	}
}

public struct AskUserResult: Codable, Equatable, Sendable {
	public var ticket: String

	public init(ticket: String) {
		self.ticket = ticket
	}
}
