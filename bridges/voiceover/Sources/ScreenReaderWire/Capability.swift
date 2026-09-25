// ROLE: entity, what a connected bridge can do, announced once per session in `hello`.
// Not an enum: a consumer must ignore a capability string it does not know, and an enum would reject it.
// A typo in a static member is therefore a capability nobody advertises, not a compile error.

public struct Capability: RawRepresentable, Codable, Hashable, Sendable {
	public let rawValue: String

	public init(rawValue: String) {
		self.rawValue = rawValue
	}

	public static let speech = Capability(rawValue: "speech")
	public static let braille = Capability(rawValue: "braille")
	public static let gestures = Capability(rawValue: "gestures")
	public static let focus = Capability(rawValue: "focus")
	public static let state = Capability(rawValue: "state")
	public static let config = Capability(rawValue: "config")
	public static let interact = Capability(rawValue: "interact")
	public static let typing = Capability(rawValue: "typing")
	public static let log = Capability(rawValue: "log")
	public static let guidance = Capability(rawValue: "guidance")
	public static let document = Capability(rawValue: "document")

	public static let known: Set<Capability> = [
		.speech, .braille, .gestures, .focus, .state, .config,
		.interact, .typing, .log, .guidance, .document,
	]

	public var isKnown: Bool { Capability.known.contains(self) }
}
