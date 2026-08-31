// A hand-written fake for the AccessibilityTrust adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/AccessibilityTrust.swift.
//
// IT COUNTS READS, AND THAT IS THE POINT OF THE FILE. The seam exists so that
// focus can pick a route from a permission WITHOUT being able to ask for one --
// every call to `PermissionBroker.request` in this repository is in a command
// handler about to post a system event, and 13.8's lever is worth exactly what
// its checkability is worth. A double that only answered a Bool could not show that focus asked the
// cheap question once and the expensive one never.
//
// The real one is `TCCPermissionBroker`, which answers this seam AND the domain's
// PermissionBroker port -- one leaf, two interfaces at two layers. This fake
// deliberately does NOT do both: a test that wants to prove focus never touched
// the broker needs the two objects to be distinguishable.

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
