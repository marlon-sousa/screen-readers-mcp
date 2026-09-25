import VoiceOverBridgeAdapters

public final class FakeAccessibilityTree: AccessibilityTree {
	/// What the focused element carries. Nil means nothing is focused.
	public var element: [String: AccessibilityValue]?

	public var failure: AccessibilityTreeFailure?

	public private(set) var queries: [(pid: Int32, attributes: [String])] = []

	public init(element: [String: AccessibilityValue]? = nil) {
		self.element = element
	}

	public func focusedElement(pid: Int32, attributes: [String]) throws -> [String: AccessibilityValue]? {
		queries.append((pid: pid, attributes: attributes))
		if let failure { throw failure }
		return element
	}
}
