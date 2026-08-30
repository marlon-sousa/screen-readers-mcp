// swift-tools-version: 6.0
// THE MODULE GRAPH IS THE ARCHITECTURE TEST.
//
// Both halves of this repo use the same hexagonal design, and the NVDA bridge
// enforces it by convention and review. Swift can enforce it at BUILD time and
// costs nothing for the privilege: a file that imports a module this target does
// not depend on does not compile. That is a better rendering of the same rule,
// so the dependency edges below are load-bearing rather than descriptive.
//
// VoiceOverBridgeApp DOES NOT YET DEPEND ON THE DOMAIN OR THE ADAPTERS, and
// this comment used to say 13.4 would give it them. It does not, deliberately:
// nothing in 13.4 makes the app DO anything -- the control dialog that starts
// and stops the server is 13.10 -- and build.sh compiles the app by handing
// swiftc one file, so an unused dependency edge here would break the shippable
// artifact in exchange for nothing. 13.10 adds the edge and teaches build.sh the
// module search path in the same breath. Today the app is the container and
// nothing more, because a macOS app extension cannot be installed on its own:
// the .appex ships inside an app's Contents/PlugIns.
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
		// The headless launcher. NOT part of the shipped bundle -- build.sh does
		// not copy it -- because it exists to make the bridge listen from a
		// terminal, which is what a live check needs and what nothing else can do
		// until the control dialog lands in 13.10.
		.executable(name: "BridgeListener", targets: ["BridgeListener"]),
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

		// ELEMENT 3, the bridge session -- and THE HEXAGON'S PURE CORE. Ports,
		// controllers and entities, and nothing else: no AppKit, no AVFoundation,
		// no sockets, no JSON framing. It depends on the wire binding because the
		// contract is the vocabulary it speaks, and on nothing else of ours.
		//
		// THE EDGE THAT DOES NOT COMPILE IS THE ARCHITECTURE TEST. A domain file
		// that imported VoiceOverBridgeAdapters would fail to build, which is a
		// better rendering of lane 1's convention-and-review rule and costs
		// nothing.
		.target(
			name: "VoiceOverBridgeDomain",
			dependencies: ["ScreenReaderWire"],
			path: "Sources/VoiceOverBridgeDomain"
		),

		// The only place macOS frameworks, the filesystem and real IO live -- plus
		// Wiring, the composition root, which is here rather than in the app
		// because SwiftPM cannot import an executable target into a test target
		// and a composition root nothing can exercise is where a wiring mistake
		// would survive every test.
		.target(
			name: "VoiceOverBridgeAdapters",
			dependencies: ["VoiceOverBridgeDomain", "ScreenReaderWire"],
			path: "Sources/VoiceOverBridgeAdapters"
		),

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

		// The launcher, kept for the same reason the probe is: a check's
		// dependencies are versioned rather than improvised in a scratch directory.
		.executableTarget(
			name: "BridgeListener",
			dependencies: ["VoiceOverBridgeAdapters", "VoiceOverBridgeDomain"],
			path: "Sources/BridgeListener"
		),

		// The container app. It exists because the system registers an .appex from
		// inside an app's Contents/PlugIns, so "the voice did not appear" is never
		// ambiguous between a broken app and a broken extension.
		.executableTarget(name: "VoiceOverBridgeApp", path: "Sources/VoiceOverBridgeApp"),

		// Tests/ mirrors Sources/ file for file. THE FAKES NOW LIVE IN A TARGET OF
		// THEIR OWN, which is the question 13.3 left open answering itself: the
		// domain's tests and the adapters' tests and the integration scenarios all
		// need the SAME doubles -- a fake clock, a fake channel, a fake transcript
		// -- and three copies of a stateful fake is three chances for one of them
		// to drift into agreeing with the code instead of with the port.
		//
		// CaptureVoiceTests keeps its own Fakes/ directory, and that is not an
		// oversight: CaptureVoice depends on nothing of ours by hard rule, so its
		// doubles stand in for ITS ports and nothing outside that module may use
		// them. A shared target holding both would be the first thread of the
		// dependency that rule exists to prevent.
		.target(
			name: "Fakes",
			dependencies: ["VoiceOverBridgeDomain", "VoiceOverBridgeAdapters", "ScreenReaderWire"],
			path: "Tests/Fakes"
		),
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

		.testTarget(
			name: "VoiceOverBridgeDomainTests",
			dependencies: ["VoiceOverBridgeDomain", "ScreenReaderWire", "Fakes"],
			path: "Tests/VoiceOverBridgeDomainTests"
		),

		.testTarget(
			name: "VoiceOverBridgeAdaptersTests",
			dependencies: ["VoiceOverBridgeAdapters", "VoiceOverBridgeDomain", "ScreenReaderWire", "Fakes"],
			path: "Tests/VoiceOverBridgeAdaptersTests"
		),

		// HEADLESS SCENARIOS THAT DRIVE THE REAL STACK -- the real Session over the
		// real JsonLinesChannel over a loopback transport, with a fake reader edge.
		// They are the analogue of lane 1's tests/integration/, they run in CI on
		// macOS, and they are what would catch a wiring mistake that every unit
		// test passes. Live-VoiceOver scenarios are NOT here: they live behind the
		// bridge's `live` tier and never run in CI.
		.testTarget(
			name: "IntegrationTests",
			dependencies: [
				"VoiceOverBridgeAdapters", "VoiceOverBridgeDomain", "ScreenReaderWire", "Fakes",
			],
			path: "Tests/Integration"
		),
	],
	swiftLanguageModes: [.v5]
)
