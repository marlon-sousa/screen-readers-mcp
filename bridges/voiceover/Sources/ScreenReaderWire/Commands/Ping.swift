// ROLE: entity -- `ping`'s result. The command has no params.
//
// Pure. Built by the Ping handler (entry 13.4), which is the ONLY handler that
// does not reset the inactivity watchdog: a heartbeat that kept the session
// alive would defeat the watchdog it is reporting to.
//
// `suppressing` is nil when the bridge cannot tell whether speech is currently
// being suppressed -- a third answer, not a false one.

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
