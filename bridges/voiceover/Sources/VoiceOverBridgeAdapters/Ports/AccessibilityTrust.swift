// ROLE: adapter seam asking whether this process may read another application's accessibility tree.
// IMPLEMENTED BY: TCCPermissionBroker, which also answers the domain's PermissionBroker, and FakeAccessibilityTrust.
// USED BY: VoiceOverFocusInspector.
// Never prompts: this is `AXIsProcessTrusted` with no options, because reading focus must not cost the person a consent decision.

public protocol AccessibilityTrust: AnyObject {
	/// Whether this process is trusted to use the accessibility API.
	/// "Not yet asked" and "refused" both answer false.
	func isTrusted() -> Bool
}
