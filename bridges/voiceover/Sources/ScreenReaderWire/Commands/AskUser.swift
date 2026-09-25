// ROLE: entity, `askUser`'s params and result.
// The result is a ticket so asking never blocks the dispatch loop; `waitForUserReply` collects the reply.

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
