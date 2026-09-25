import VoiceOverBridgeDomain

public final class FakeFocusInspector: FocusInspector {
	public var snapshot = FocusSnapshot()

	public var failure: FocusError?

	public private(set) var reads = 0

	public init() {}

	public func focusInfo() throws -> FocusSnapshot {
		reads += 1
		if let failure { throw failure }
		return snapshot
	}
}
