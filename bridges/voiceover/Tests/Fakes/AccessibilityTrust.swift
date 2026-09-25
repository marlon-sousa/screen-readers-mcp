// Deliberately not also a PermissionBroker, so a test can prove focus never touched the broker.

import VoiceOverBridgeAdapters

public final class FakeAccessibilityTrust: AccessibilityTrust {
	public var trusted: Bool

	public private(set) var reads = 0

	public init(trusted: Bool = false) {
		self.trusted = trusted
	}

	public func isTrusted() -> Bool {
		reads += 1
		return trusted
	}
}
