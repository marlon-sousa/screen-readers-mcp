// ROLE: adapter seam -- which application is in front, and how to address it.
//
// NOT A DOMAIN PORT: the domain has no idea that "where am I" starts with a pid
// on this platform. This is the seam between two adapters, which is the only way
// one adapter may depend on another (AGENTS.md).
//
// IMPLEMENTED BY: WorkspaceFrontmostApplication (the leaf, NSWorkspace) and
// FakeFrontmostApplication (Tests/Fakes).
// USED BY: VoiceOverFocusInspector, on BOTH routes -- the accessibility tree
// needs the pid to address an application element, and `appModule` is answered
// from here whichever route filled in the rest.
//
// IT COSTS NO PERMISSION AT ALL, which is why it can be asked before the route
// is chosen: the frontmost application is public information on macOS, unlike
// anything inside its window.
//
// THE IDENTITY IS A BUNDLE IDENTIFIER, NEVER A NAME, and that is the lane's
// no-reader-strings rule reaching one layer further out. Measured 2026-08-30
// while writing `scripts/voiceover_keyboard.sh`: `lsappinfo` answers with the
// LOCALIZED application name -- TextEdit is "Editor de Texto" on the
// maintainer's machine -- so anything that compared names would work in English
// and quietly report the wrong application everywhere else. `com.apple.TextEdit`
// is the same string on every machine, so it is what `appModule` carries.

/// Enough of an application to address it and to name it on the wire.
public struct ApplicationIdentity: Equatable, Sendable {
	/// What `appModule` reports. Optional because an application may genuinely
	/// have none -- a bare executable launched from a terminal -- and "no bundle
	/// identifier" is an answer rather than a fault.
	public let bundleIdentifier: String?

	/// What the accessibility tree is addressed by. See `AXAccessibilityTree`,
	/// which explains why the per-application element is the only one that works.
	public let processIdentifier: Int32

	public init(bundleIdentifier: String?, processIdentifier: Int32) {
		self.bundleIdentifier = bundleIdentifier
		self.processIdentifier = processIdentifier
	}
}

public protocol FrontmostApplication: AnyObject {
	/// The application currently in front, or nil if the system reports none.
	func frontmostApplication() -> ApplicationIdentity?
}
