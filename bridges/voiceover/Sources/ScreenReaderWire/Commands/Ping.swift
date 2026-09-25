// ROLE: entity, `ping`'s result; the command has no params.
// `suppressing` is nil when the bridge cannot tell whether speech is being suppressed.

public struct PingResult: Codable, Equatable, Sendable {
	public var ok: Bool = true
	public var suppressing: Bool?

	public init(ok: Bool = true, suppressing: Bool? = nil) {
		self.ok = ok
		self.suppressing = suppressing
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		ok = try box.decode(Bool.self, forKey: .ok, orDefault: ok)
		suppressing = try box.decodeIfPresent(Bool.self, forKey: .suppressing)
	}
}
