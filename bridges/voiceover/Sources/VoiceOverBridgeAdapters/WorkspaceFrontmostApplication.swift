// ROLE: LEAF adapter -- IMPLEMENTS the FrontmostApplication seam over
// NSWorkspace, and that is the whole file.
//
// BUILT BY: Wiring, once per process. USED BY: VoiceOverFocusInspector, through
// the seam, never directly.
//
// NO TEST FILE: it makes no decisions. What the identity is used FOR -- a pid to
// address the accessibility tree with, a bundle identifier to report as
// `appModule` -- is decided one layer up, and there is nothing here that
// `NSWorkspace` does not already guarantee.
//
// IT COSTS NO PERMISSION. The frontmost application is public information on
// macOS: this answers on a machine that has granted nothing, which is why the
// adapter above can ask it before it knows which route it is taking.
//
// THE BUNDLE IDENTIFIER, NEVER `localizedName`. The name is rendered in the
// user's own language -- TextEdit is "Editor de Texto" on the maintainer's
// machine -- and `appModule` is a field an agent compares. See the seam's
// header.

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
