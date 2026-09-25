import VoiceOverBridgeAdapters

public final class FakeFrontmostApplication: FrontmostApplication {
	/// A bundle identifier, never a rendered name.
	public var application: ApplicationIdentity?

	public private(set) var reads = 0

	public init(
		application: ApplicationIdentity? = ApplicationIdentity(
			bundleIdentifier: "com.apple.TextEdit", processIdentifier: 4242
		)
	) {
		self.application = application
	}

	public func frontmostApplication() -> ApplicationIdentity? {
		reads += 1
		return application
	}
}
