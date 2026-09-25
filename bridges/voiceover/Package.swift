// swift-tools-version: 6.0
// SwiftPM cannot emit .app or .appex bundles, so build.sh assembles them.
// Swift 5 language mode: the capture voice shares state across three threads under an os_unfair_lock,
// which Swift 6 strict concurrency cannot express.
import PackageDescription

let package = Package(
	name: "VoiceOverBridge",
	platforms: [.macOS(.v14)],
	products: [
		// Built as a framework by build.sh: compiled into the appex executable on macOS 15,
		// enumeration worked and every in-process synthesis failed silently.
		.library(name: "CaptureVoice", targets: ["CaptureVoice"]),
		.executable(name: "CaptureProbe", targets: ["CaptureProbe"]),
		// Not part of the shipped bundle.
		.executable(name: "BridgeListener", targets: ["BridgeListener"]),
		// A product because the Go conformance tier builds it with `swift build --product ConformanceBridge`.
		.executable(name: "ConformanceBridge", targets: ["ConformanceBridge"]),
	],
	targets: [
		// Depends on nothing of ours: every byte of it runs inside the user's screen reader.
		.target(name: "CaptureVoice", path: "Sources/CaptureVoice"),

		// Depends on nothing beyond Foundation; scripts/drift.py checks it against specs/wire/v1/schema.json.
		.target(name: "ScreenReaderWire", path: "Sources/ScreenReaderWire"),

		// A .app assembled by build.sh that depends on this target must copy
		// VoiceOverBridge_VoiceOverBridgeDomain.bundle into Contents/Resources, or loading a document traps.
		.target(
			name: "VoiceOverBridgeDomain",
			dependencies: ["ScreenReaderWire"],
			path: "Sources/VoiceOverBridgeDomain",
			resources: [.copy("Entities/Documents")]
		),

		.target(
			name: "VoiceOverBridgeAdapters",
			dependencies: ["VoiceOverBridgeDomain", "ScreenReaderWire"],
			path: "Sources/VoiceOverBridgeAdapters"
		),

		// A library target: build.sh links it as the app extension's executable, entry point _NSExtensionMain.
		.target(
			name: "CaptureVoiceExtension",
			dependencies: ["CaptureVoice"],
			path: "Sources/CaptureVoiceExtension"
		),

		.executableTarget(
			name: "CaptureProbe",
			dependencies: ["CaptureVoice"],
			path: "Sources/CaptureProbe"
		),

		.executableTarget(
			name: "BridgeListener",
			dependencies: ["VoiceOverBridgeAdapters", "VoiceOverBridgeDomain"],
			path: "Sources/BridgeListener"
		),

		// The system registers an .appex only from inside an app's Contents/PlugIns.
		.executableTarget(name: "VoiceOverBridgeApp", path: "Sources/VoiceOverBridgeApp"),

		.target(
			name: "Fakes",
			dependencies: ["VoiceOverBridgeDomain", "VoiceOverBridgeAdapters", "ScreenReaderWire"],
			path: "Tests/Fakes"
		),
		// Never copy it into the bundle: it links the fakes, so it only pretends to drive VoiceOver.
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
