// swift-tools-version: 6.0
// THE MODULE GRAPH IS THE ARCHITECTURE TEST.
//
// Both halves of this repo use the same hexagonal design, and the NVDA bridge
// enforces it by convention and review. Swift can enforce it at BUILD time and
// costs nothing for the privilege: a file that imports a module this target does
// not depend on does not compile. That is a better rendering of the same rule,
// so the dependency edges below are load-bearing rather than descriptive.
//
// WHAT IS NOT HERE YET, and which entry brings it:
//   * VoiceOverBridgeDomain       -- 13.4, ports/controllers/entities
//   * VoiceOverBridgeAdapters     -- 13.4, the macOS/AppleScript/IO edge
// VoiceOverBridgeApp then gains those two and ScreenReaderWire as dependencies.
// Today it is the container app and nothing more, because a macOS app extension
// cannot be installed on its own -- the .appex ships inside an app's
// Contents/PlugIns.
//
// PACKAGE.SWIFT IS NOT THE BUILD. SwiftPM cannot emit .app or .appex bundles,
// so build.sh assembles them; this manifest is what `swift build` and
// `swift test` compile, which is what makes the graph above a gate.
//
// SWIFT 5 LANGUAGE MODE, deliberately. The capture voice is shared mutable
// state reached from three threads by design -- the system's request thread, the
// synthesis queue and the audio thread -- and its safety argument is the ring's
// lock discipline, written and measured against a live reader (spec 0041). Swift
// 6's strict concurrency checking would reject that shape and ask for actors,
// which cannot be used from a render block. Revisit it when the checker can
// express "this is guarded by an os_unfair_lock"; not before.
import PackageDescription

let package = Package(
	name: "VoiceOverBridge",
	// The measurements in spec 0041 were made on macOS 15.0, and the provider
	// route needs nothing newer than 14: AVSpeechSynthesisProviderAudioUnit is
	// macOS 13. Kept at the spike's own floor rather than raised silently.
	platforms: [.macOS(.v14)],
	products: [
		// Built as a FRAMEWORK by build.sh, and that is not a packaging
		// preference: a speech provider is loaded both out of process (by
		// axassetsd, through NSExtensionPrincipalClass) and in process (dlopened
		// into whatever is speaking), and the in-process path can only find the
		// class if it lives in a framework rather than in the appex executable.
		// Measured: compiled into the executable, enumeration worked and every
		// synthesis failed silently.
		.library(name: "CaptureVoice", targets: ["CaptureVoice"]),
		.executable(name: "CaptureProbe", targets: ["CaptureProbe"]),
	],
	targets: [
		// ELEMENT 1 of the five (spec 0046, part 3): the speech provider, its own
		// small hexagon, in its own process AND dlopened into every client that
		// speaks -- VoiceOver included.
		//
		// IT DEPENDS ON NOTHING OF OURS, AND THAT IS A HARD RULE. Every byte it
		// carries runs inside the user's screen reader, which is the same argument
		// that makes the shared wire module stdlib-only, reached from the other
		// direction. It never imports the domain, the wire binding, or anything
		// that would grow a dependency later.
		.target(name: "CaptureVoice", path: "Sources/CaptureVoice"),

		// The wire contract's Swift binding (entry 13.3). IT DEPENDS ON NOTHING,
		// including nothing of Apple's beyond Foundation, because it is the
		// contract rendered as value types -- the domain and the adapters both
		// speak it, and neither may reach back through it. Hand-written per spec
		// 0043 and gated against specs/wire/v1/schema.json by scripts/drift.py:
		// no language server crosses the Go/Python boundary and none crosses this
		// one either, so the schema is the only index the three bindings share.
		.target(name: "ScreenReaderWire", path: "Sources/ScreenReaderWire"),

		// The .appex stub. A LIBRARY target here, not an executable, because its
		// entry point is _NSExtensionMain rather than main() -- build.sh passes
		// the linker flags that make it an app extension's executable. SwiftPM's
		// job for this target is to prove it compiles and links against the
		// framework; it cannot produce the bundle.
		.target(
			name: "CaptureVoiceExtension",
			dependencies: ["CaptureVoice"],
			path: "Sources/CaptureVoiceExtension"
		),

		// KEPT, per spec 0046's amendment to board 13.2. It answers "is the capture
		// voice published?" without a human squinting at a settings pane, which
		// makes it a live-checklist DEPENDENCY -- and a checklist's dependencies
		// are versioned rather than improvised (the 2026-08-22 rule).
		.executableTarget(
			name: "CaptureProbe",
			dependencies: ["CaptureVoice"],
			path: "Sources/CaptureProbe"
		),

		// The container app. It exists because the system registers an .appex from
		// inside an app's Contents/PlugIns, so "the voice did not appear" is never
		// ambiguous between a broken app and a broken extension.
		.executableTarget(name: "VoiceOverBridgeApp", path: "Sources/VoiceOverBridgeApp"),

		// Tests/ mirrors Sources/ file for file, and the FAKES live in here rather
		// than in a target of their own. 13.3 added a second test target and did
		// NOT change that: a shared Fakes target is worth its indirection once two
		// targets need the SAME double, and the wire binding has no ports to fake
		// -- it is value types, tested with values. 13.4 is where the question is
		// live again.
		.testTarget(
			name: "CaptureVoiceTests",
			dependencies: ["CaptureVoice"],
			path: "Tests/CaptureVoiceTests"
		),

		.testTarget(
			name: "ScreenReaderWireTests",
			dependencies: ["ScreenReaderWire"],
			path: "Tests/ScreenReaderWireTests"
		),
	],
	swiftLanguageModes: [.v5]
)
