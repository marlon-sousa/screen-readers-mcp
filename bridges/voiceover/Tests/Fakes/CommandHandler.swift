import ScreenReaderWire
import VoiceOverBridgeDomain

public final class FakeHandler: CommandHandler {
	public let resetsInactivity: Bool
	public let availableBeforeHello: Bool
	public let mutatesReader: Bool

	public private(set) var calls: [Request] = []
	public var result: any Encodable = AckResult()
	public var failure: (any Error)?
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
