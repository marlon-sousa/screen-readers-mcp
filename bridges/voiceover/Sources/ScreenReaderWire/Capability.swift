// ROLE: entity -- what a connected bridge can do, announced once per session in
// `hello`.
//
// Pure. Built by the `hello` handler (entry 13.4) from what this build actually
// implements, and read by the server to decide which MCP tools to gate.
//
// NOT AN ENUM, AND THE REASON IS IN THE CONTRACT: protocol.md requires a
// consumer to IGNORE a capability string it does not know, so the set can grow
// without breaking an older peer. A Swift enum decodes an unknown raw value as a
// failure, which would turn a newer peer's added capability into a rejected
// handshake -- the exact outcome the rule exists to prevent. So this is a raw
// string that RETAINS what it was given, with the known vocabulary as static
// members, and `isKnown` for the one caller that wants to tell them apart.
//
// The consequence, stated rather than discovered: comparing capabilities is
// comparing strings, so a typo in a static member below is a capability nobody
// advertises rather than a compile error. That is what the drift gate reads this
// file for.

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

	/// The vocabulary this build of the contract knows. A capability outside it
	/// is not an error -- see the header.
	public static let known: Set<Capability> = [
		.speech, .braille, .gestures, .focus, .state, .config,
		.interact, .typing, .log, .guidance, .document,
	]

	public var isKnown: Bool { Capability.known.contains(self) }
}
