// ROLE: the interface every command handler implements -- one handler per wire
// command, dispatched to by the Session, which wraps whatever it returns.
//
// USED BY: the Session (dispatch) and Registry (which builds the map).
// OWNS: `CommandError`, the failure a handler raises to answer with an error
// frame. Both live here because they are one contract.
//
// NO TEST FILE, LIKE A PORT. There is no behaviour here: an interface plus the
// policy flags the dispatch loop reads instead of asking `if cmd == "ping"`.
//
// THE CONTRACT IS DELIBERATELY THIN, so that id handling, error wrapping and the
// watchdogs stay in ONE place:
//   * `execute` returns the command's wire RESULT shape; the Session puts it in
//     a Response with the request's id.
//   * to FAIL, a handler THROWS -- a CommandError of its own, or a
//     ValidationError from reading its params. The Session turns either into an
//     error frame and, once established, carries on; a failure before `hello`
//     ends the handshake.

import ScreenReaderWire

/// The longest ANY single blocking command may hold the session thread.
///
/// Comfortably inside the 120 s command-inactivity window
/// (`SessionConfig.inactivityTimeout`), which is measured from the moment a
/// command is DISPATCHED and is deliberately not refreshed when a handler
/// returns: inactivity answers "has the agent abandoned this session?", so a
/// blocking handler must not extend it. A command allowed to block longer would
/// answer the agent and have the session torn down under it one line later.
///
/// LIVES HERE, on the shared handler module, rather than on whichever blocking
/// command needed it first: it is a property of the SESSION's watchdog, not of
/// user replies. Lane 1 puts its `MAX_POLL_TIMEOUT` in the same place, with the
/// same value, for the same reason -- and clamping in the bridge protects every
/// client, not only the one whose tool schema is polite.
public let maxPollTimeout: Double = 110.0

/// A handler-level failure: a version mismatch, a mode this build cannot carry
/// out, a command whose preconditions are not met. Distinct from a transport
/// fault and from a validation fault, both of which have their own types.
public struct CommandError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol CommandHandler: AnyObject {
	/// Whether a successful call resets the command-inactivity watchdog. `ping`
	/// is the one handler that says no: it proves the process is alive, which is
	/// the heartbeat's question, and says nothing about whether the agent is
	/// still testing.
	var resetsInactivity: Bool { get }

	/// Whether this command is legal before `hello`. Only the hello handler says
	/// yes; everything else is refused until the handshake completes.
	var availableBeforeHello: Bool { get }

	/// Whether this command MOVES the user's machine -- a keypress, typed text --
	/// rather than only observing it. Nothing at 13.4 does; the input entries
	/// (13.7, 13.8) are the first, and an observe-only session (spec 0017) is
	/// what reads this.
	///
	/// The default is `false` and the failure mode of forgetting to opt in is
	/// "allowed", so a mutating command must set it deliberately. The registry's
	/// enumeration test is what makes forgetting visible.
	var mutatesReader: Bool { get }

	/// Run the command and return its wire result, or throw to fail it.
	func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable
}

public extension CommandHandler {
	var resetsInactivity: Bool { true }
	var availableBeforeHello: Bool { false }
	var mutatesReader: Bool { false }
}
