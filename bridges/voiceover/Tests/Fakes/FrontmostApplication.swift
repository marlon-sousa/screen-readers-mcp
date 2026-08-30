// A hand-written fake for the FrontmostApplication adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/FrontmostApplication.swift.
//
// The default answers a real-looking identity rather than nil, because "an
// application is in front" is the ordinary case and a nil default would make
// every test that does not care about it exercise the empty path by accident.
// Nil is available, and it is what a test asks for when it wants the case where
// the system reports nothing in front.

import VoiceOverBridgeAdapters

public final class FakeFrontmostApplication: FrontmostApplication {
	/// Who is in front. A BUNDLE IDENTIFIER, never a name -- see the seam's
	/// header on why nothing in this lane compares a rendered application name.
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
