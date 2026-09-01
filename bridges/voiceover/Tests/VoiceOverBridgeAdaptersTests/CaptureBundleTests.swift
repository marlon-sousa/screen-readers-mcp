// Mirrors Sources/VoiceOverBridgeAdapters/CaptureBundle.swift.
//
// Two things are worth asserting about a packaging declaration: that the appex
// is derived from the app rather than spelled twice, and that the two names are
// still in the shape `build.sh` extracts them with. The second is the one that
// would fail silently -- a rename lands, the shell's `sed` finds nothing, and
// `register()` points `lsregister -f` at a path that is not there.

import Foundation
import Testing

@testable import VoiceOverBridgeAdapters

@Suite("CaptureBundle")
struct CaptureBundleTests {
	@Test("the appex is derived from the app, at the place macOS requires")
	func theAppexIsInsideTheApp() {
		let paths = CaptureBundlePaths.inside(app: "/Applications/VoiceOverCaptureSpike.app")
		#expect(paths.app == "/Applications/VoiceOverCaptureSpike.app")
		#expect(
			paths.appex
				== "/Applications/VoiceOverCaptureSpike.app/Contents/PlugIns/\(captureExtensionName).appex")
	}

	@Test("a directory names the app inside it")
	func aDirectoryNamesTheApp() {
		let paths = CaptureBundlePaths.inside(directory: "/somewhere/build")
		#expect(paths.app == "/somewhere/build/\(captureAppName).app")
		#expect(paths.appex.hasPrefix(paths.app))
	}

	@Test("THE NAMES ARE THE ONES build.sh READS, and this is what catches a rename")
	func theBuildScriptReadsTheseNames() throws {
		// The BridgeVersion pattern (13.11): declared in Swift, extracted by `sed`
		// before anything is compiled. If the declarations ever stop being a `let`
		// with a one-line double-quoted literal, the shell reads an empty string
		// and assembles a bundle nothing can register.
		let source = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Sources/VoiceOverBridgeAdapters/CaptureBundle.swift")
		let text = try String(contentsOf: source, encoding: .utf8)
		#expect(text.contains("public let captureAppName = \"\(captureAppName)\""))
		#expect(text.contains("public let captureExtensionName = \"\(captureExtensionName)\""))
	}
}
