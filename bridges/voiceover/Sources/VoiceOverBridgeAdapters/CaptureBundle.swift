// ROLE: packaging declaration, and the pure derivation of the two paths registration needs.
// USED BY: Wiring, which asks it for the path pair, and `build.sh`, which reads the two names out of this file.
// Keep each name a `public let` with a double-quoted literal on one line: `build.sh` extracts it with `sed`.

import Foundation

public let captureAppName = "VoiceOverCaptureSpike"

public let captureExtensionName = "CaptureVoice"

/// Registration uses the pair in order: `lsregister -f` on the app, then `pluginkit -a` on the appex.
public struct CaptureBundlePaths: Equatable, Sendable {
	public let app: String
	public let appex: String

	public init(app: String, appex: String) {
		self.app = app
		self.appex = appex
	}

	public static func inside(app: String) -> CaptureBundlePaths {
		CaptureBundlePaths(
			app: app,
			appex: URL(fileURLWithPath: app)
				.appendingPathComponent("Contents/PlugIns")
				.appendingPathComponent("\(captureExtensionName).appex")
				.path
		)
	}

	public static func inside(directory: String) -> CaptureBundlePaths {
		inside(
			app: URL(fileURLWithPath: directory)
				.appendingPathComponent("\(captureAppName).app").path)
	}
}
