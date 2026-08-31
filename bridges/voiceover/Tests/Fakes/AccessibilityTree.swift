// A hand-written stateful fake for the AccessibilityTree adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/AccessibilityTree.swift.
//
// IT RECORDS THE QUERY, not just that a query happened: the pid it was addressed
// to and the attribute names it was asked for. Which attributes focus asks for
// is a decision -- `AXTitle` before `AXDescription`, `AXRole` and never
// `AXRoleDescription`, three booleans that become states -- and the decision
// lives in the adapter above, so this is where a test can see it.
//
// It answers a table, which is what makes both of the seam's honest outcomes
// available: nil for "nothing is focused there" (an ANSWER -- an application
// between windows, or VoiceOver's own process, which publishes no tree at all),
// and a dictionary whose missing keys are attributes the element does not carry.

import VoiceOverBridgeAdapters

public final class FakeAccessibilityTree: AccessibilityTree {
	/// What the focused element carries. Nil means nothing is focused.
	public var element: [String: AccessibilityValue]?

	/// When set, the read fails with this instead of answering.
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
