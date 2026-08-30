// A hand-written stateful double for the CommandHandler interface, mirroring
// Sources/VoiceOverBridgeDomain/Controllers/Commands/CommandHandler.swift.
//
// NOT A PORT DOUBLE, STRICTLY -- CommandHandler is a controller interface -- but
// it belongs here for the same reason the port doubles do: the session's tests
// are about DISPATCH, not about any command, and a session driven by real
// handlers would be asserting on hello's behaviour every time it wanted to prove
// that a ping does not reset the inactivity watchdog.

import ScreenReaderWire
import VoiceOverBridgeDomain

public final class FakeHandler: CommandHandler {
	public let resetsInactivity: Bool
	public let availableBeforeHello: Bool
	public let mutatesReader: Bool

	/// Every request this handler was given, in order.
	public private(set) var calls: [Request] = []
	/// What to answer with. An AckResult unless a test says otherwise.
	public var result: any Encodable = AckResult()
	/// When set, `execute` throws it instead of answering.
	public var failure: (any Error)?
	/// Run before answering: how a test makes a handler close the session, advance
	/// a clock, or populate the context the way hello would.
	public var onExecute: ((SessionContext, Request) -> Void)?

	public init(
		resetsInactivity: Bool = true,
		availableBeforeHello: Bool = false,
		mutatesReader: Bool = false
	) {
		self.resetsInactivity = resetsInactivity
		self.availableBeforeHello = availableBeforeHello
		self.mutatesReader = mutatesReader
	}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		calls.append(request)
		onExecute?(context, request)
		if let failure { throw failure }
		return result
	}
}
