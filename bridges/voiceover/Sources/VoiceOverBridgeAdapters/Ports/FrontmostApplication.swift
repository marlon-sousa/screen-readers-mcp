// ROLE: adapter seam naming the frontmost application and how to address it.
// IMPLEMENTED BY: WorkspaceFrontmostApplication and FakeFrontmostApplication.
// USED BY: VoiceOverFocusInspector, on both focus routes.
// Costs no permission, so it can be asked before a focus route is chosen.
// Identity is a bundle identifier, never a name: on macOS 15 `lsappinfo` reports localized names, such as "Editor de Texto" for TextEdit.

public struct ApplicationIdentity: Equatable, Sendable {
	/// Nil for an application with no bundle, such as a bare executable; an answer, not a fault.
	public let bundleIdentifier: String?

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
