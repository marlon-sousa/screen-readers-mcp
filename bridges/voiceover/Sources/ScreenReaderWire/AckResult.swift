// ROLE: entity, the result of a command with nothing to report.
// `ok` defaults to true, so `{}` means it worked; a failure is an error frame, never `ok: false`.

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
