// ROLE: leaf adapter implementing the FrontmostApplication seam over NSWorkspace.
// BUILT BY: Wiring, once per process.
// USED BY: VoiceOverFocusInspector, through the seam.
// It needs no permission, so it answers on a machine that has granted nothing.

import AppKit

public final class WorkspaceFrontmostApplication: FrontmostApplication {
	public init() {}

	public func frontmostApplication() -> ApplicationIdentity? {
		guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
		return ApplicationIdentity(
			bundleIdentifier: application.bundleIdentifier,
			processIdentifier: application.processIdentifier
		)
	}
}
