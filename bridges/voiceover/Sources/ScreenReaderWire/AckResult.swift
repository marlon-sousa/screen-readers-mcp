// ROLE: entity -- the shape a command with nothing to report answers with.
//
// Pure. It is `announce`'s result and `bye`'s -- two commands in two files,
// which is why it is a file of its own rather than living with either.
//
// `ok` DEFAULTS TO TRUE, which is not a Swift convenience but the contract's
// own default: a peer that sends `{}` has said "it worked". A failure is not an
// AckResult with ok=false, it is an error frame (see Envelope).

public struct AckResult: Codable, Equatable, Sendable {
	public var ok: Bool = true

	public init(ok: Bool = true) {
		self.ok = ok
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		ok = try box.decode(Bool.self, forKey: .ok, orDefault: ok)
	}
}
