// ROLE: entity -- `waitForUserReply`'s params and result.
//
// Pure. The other half of `askUser`: it waits on a ticket, through the Clock
// port like every other wait in this contract.
//
// THE TIMEOUT IS 30 SECONDS RATHER THAN 5, because the thing being waited for is
// a human reading a prompt and deciding, not a machine emitting an utterance.
// `answered == false` is a normal answer -- the human did not reply in time.

public struct WaitForUserReplyParams: Codable, Equatable, Sendable {
	public var ticket: String
	public var timeout: Double = 30.0

	public init(ticket: String, timeout: Double = 30.0) {
		self.ticket = ticket
		self.timeout = timeout
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		ticket = try box.decode(String.self, forKey: .ticket)
		timeout = try box.decode(Double.self, forKey: .timeout, orDefault: timeout)
	}
}

public struct WaitForUserReplyResult: Codable, Equatable, Sendable {
	public var answered: Bool
	public var text: String = ""

	public init(answered: Bool, text: String = "") {
		self.answered = answered
		self.text = text
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		answered = try box.decode(Bool.self, forKey: .answered)
		text = try box.decode(String.self, forKey: .text, orDefault: text)
	}
}
