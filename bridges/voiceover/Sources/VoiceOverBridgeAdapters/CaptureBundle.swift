// ROLE: a packaging DECLARATION, and the pure derivation of the two paths
// registration needs. No IO, no decisions about the machine.
//
// USED BY: Wiring, which resolves a directory and asks this for the pair; and by
// `build.sh`, which reads the two names out of this file with `sed`.
// USED BY NOTHING IN THE DOMAIN -- these are facts about how the bundle is
// assembled, which is exactly what `PluginKitProviderLifecycle` says it must not
// know: that class is "the place that knows what an answer means and not the
// place that knows what we are called".
//
// THE NAMES ARE DECLARED HERE AND READ BY THE BUILD, which is the pattern
// `BridgeVersion.swift` established at 13.11, for its reason. The alternative is
// `APP_NAME` in the shell script and a hard-coded `"VoiceOverCaptureSpike.app"`
// in Wiring, drifting apart the first time anybody renames anything -- and the
// failure would surface as a `register()` that runs `lsregister -f` against a
// path that is not there, which is a registration that silently does nothing on
// a machine where the bundle is plainly present.
//
// SO THE SHAPE OF THESE TWO DECLARATIONS IS LOAD-BEARING: a `public let` with a
// double-quoted literal on one line, because `build.sh` extracts them with the
// same `sed` expression it uses for the version, before anything is compiled and
// when nothing may compile at all.
//
// THE IDENTIFIERS ARE NOT HERE. `captureExtensionBundleID` and
// `captureVoiceIdentifierSuffix` live beside `ContainerFileSpeechSource`,
// because they name the CONTAINER a feed is read from and the string the system
// publishes -- they are answers, not layout. This file is only the layout, and
// the two must not be merged: the identity is frozen (renaming it costs every
// user a trip to VoiceOver Utility) while the layout is free to change with the
// build script.

import Foundation

/// The `.app` bundle's name, without its extension. Read by `build.sh`.
public let captureAppName = "VoiceOverCaptureSpike"

/// The `.appex` bundle's name, without its extension. Read by `build.sh`.
public let captureExtensionName = "CaptureVoice"

/// The two paths `ProviderLifecycle.register()` needs, and nothing else.
///
/// A pair rather than one path plus a rule, because the ORDER the two are used
/// in is the contract (`lsregister -f` on the app, THEN `pluginkit -a` on the
/// appex -- spec 0041 C1) and a caller holding both is a caller that cannot get
/// the second one wrong.
public struct CaptureBundlePaths: Equatable, Sendable {
	/// The `.app`, which LaunchServices is pointed at.
	public let app: String
	/// The `.appex` inside it, which pluginkit is pointed at.
	public let appex: String

	public init(app: String, appex: String) {
		self.app = app
		self.appex = appex
	}

	/// The pair for an app bundle at `app`.
	///
	/// `Contents/PlugIns/<name>.appex` is where macOS requires an app extension
	/// to sit and where `build.sh` puts it. Pure, so the rule is testable without
	/// a bundle on disk.
	public static func inside(app: String) -> CaptureBundlePaths {
		CaptureBundlePaths(
			app: app,
			appex: URL(fileURLWithPath: app)
				.appendingPathComponent("Contents/PlugIns")
				.appendingPathComponent("\(captureExtensionName).appex")
				.path
		)
	}

	/// The pair for a `.app` sitting in `directory`.
	public static func inside(directory: String) -> CaptureBundlePaths {
		inside(
			app: URL(fileURLWithPath: directory)
				.appendingPathComponent("\(captureAppName).app").path)
	}
}
