// ROLE: the interface every command handler implements, one handler per wire command.
// USED BY: the Session, which dispatches, and Registry, which builds the map.
// OWNS: `CommandError`, the failure a handler throws to answer with an error frame.
// A thrown error becomes an error frame; before `hello` it also ends the handshake.

import ScreenReaderWire

/// The longest any blocking command may hold the session thread; it must stay below
/// `SessionConfig.inactivityTimeout`, which is not refreshed when a handler returns.
public let maxPollTimeout: Double = 110.0

public struct CommandError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol CommandHandler: AnyObject {
	/// `ping` alone returns false: it proves the process is alive, not that the agent is active.
	var resetsInactivity: Bool { get }

	var availableBeforeHello: Bool { get }

	/// Whether this command moves the user's machine; a mutating command must opt in, because the
	/// default of `false` lets an observe-only session run it.
	var mutatesReader: Bool { get }

	func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable
}

public extension CommandHandler {
	var resetsInactivity: Bool { true }
	var availableBeforeHello: Bool { false }
	var mutatesReader: Bool { false }
}
