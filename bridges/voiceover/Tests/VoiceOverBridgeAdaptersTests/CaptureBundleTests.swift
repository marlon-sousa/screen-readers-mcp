// Mirrors Sources/VoiceOverBridgeAdapters/CaptureBundle.swift.

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
		let source = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Sources/VoiceOverBridgeAdapters/CaptureBundle.swift")
		let text = try String(contentsOf: source, encoding: .utf8)
		#expect(text.contains("public let captureAppName = \"\(captureAppName)\""))
		#expect(text.contains("public let captureExtensionName = \"\(captureExtensionName)\""))
	}
}
