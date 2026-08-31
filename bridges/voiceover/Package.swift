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
		// until the control dialog lands in 13.14.
		.executable(name: "BridgeListener", targets: ["BridgeListener"]),
		// The conformance harness (13.11): a REAL bridge with a fake reader behind
		// it, startable as a process so the Go conformance tier can drive it with
		// the real server binary. A PRODUCT rather than only a target because the
		// Go side builds it by name -- `swift build --product ConformanceBridge` --
		// and a target with no product cannot be asked for that way.
		//
		// NOT part of the shipped bundle either, and it must never become one: it
		// depends on Tests/Fakes, which is where every double that keeps a test off
		// the developer's real machine lives.
		.executable(name: "ConformanceBridge", targets: ["ConformanceBridge"]),
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
		//
		// IT CARRIES RESOURCES SINCE 13.11, AND THEY ARE DOCUMENTS RATHER THAN
		// ASSETS. `Entities/Documents/*.md` is this reader's own guidance, which by
		// the repo's rule (root AGENTS.md, invariant 9) is a .md file beside the
		// package that serves it and never a string literal in code. `embed` is
		// stdlib on the Go side and `Bundle.module` is SwiftPM's equivalent here, so
		// a pure domain target may carry them without acquiring a dependency.
		//
		// `.copy` RATHER THAN `.process`: these are markdown read verbatim, and
		// `.process` reserves the right to transform what it finds. Copy keeps the
		// bytes in the bundle exactly as they are in the repository, which is what
		// makes "the file IS the document" true.
		//
		// THE TRAP THIS DECLARATION SETS, written where whoever trips it will look:
		// SwiftPM puts the generated bundle beside the executable it built, so
		// `swift test` and `BridgeListener` find it with no help. A .app that
		// build.sh ASSEMBLES does not get it for free -- whoever gives the app the
		// bridge's dependency edge (13.14, spec 0046 amendment 12) must copy
		// `VoiceOverBridge_VoiceOverBridgeDomain.bundle` into Contents/Resources in
		// the same breath, or the failure is a runtime trap rather than a compile
		// error. Nothing in the app reads the domain today, which is why 13.11 did
		// not add that copy: a resource nothing loads is a step that cannot be
		// tested.
		.target(
			name: "VoiceOverBridgeDomain",
			dependencies: ["ScreenReaderWire"],
			path: "Sources/VoiceOverBridgeDomain",
			resources: [.copy("Entities/Documents")]
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
		// THE CONFORMANCE HARNESS: an EXECUTABLE that depends on the fakes, which is
		// a shape nothing else in this package has and which is deliberate.
		//
		// It is the Swift twin of bridges/nvda/tests/support/conformance_bridge.py,
		// and it lives under Tests/ for that file's reason: it is scaffolding a
		// CHECK depends on, and a check's dependencies are versioned rather than
		// improvised (the 2026-08-22 rule). SwiftPM has no notion of a
		// test-support executable, so it is an ordinary executable target that
		// happens to sit in Tests/ -- and `Fakes` is a plain target rather than a
		// test target, which is what makes that possible at all.
		//
		// IT MUST NEVER BE COPIED INTO THE BUNDLE. build.sh does not copy it, and
		// the reason is stronger than for the probe and the launcher: this binary
		// carries the doubles that exist to keep code away from a real reader, a
		// real grant and a real voice. Shipping it would ship a bridge that only
		// pretends to drive VoiceOver.
		.executableTarget(
			name: "ConformanceBridge",
			dependencies: [
				"VoiceOverBridgeAdapters", "VoiceOverBridgeDomain", "ScreenReaderWire", "Fakes",
			],
			path: "Tests/ConformanceBridge"
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
		//
		// IT DEPENDS ON CaptureVoice, AND THAT DOES NOT WEAKEN THE RULE ABOVE. The
		// rule is about the direction: the capture voice may import nothing of
		// ours, because every byte of it runs inside somebody's screen reader.
		// Nothing stops a TEST from importing both halves -- and 13.6 needs one
		// that does, because the marker file is a contract between two processes
		// and two halves that each pass their own tests can still disagree about
		// the bytes. CaptureProbe already depends on it for the same kind of
		// reason.
		.testTarget(
			name: "IntegrationTests",
			dependencies: [
				"VoiceOverBridgeAdapters", "VoiceOverBridgeDomain", "ScreenReaderWire", "Fakes",
				"CaptureVoice",
			],
			path: "Tests/Integration"
		),
	],
	swiftLanguageModes: [.v5]
)
