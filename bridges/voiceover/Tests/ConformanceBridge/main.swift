// A real VoiceOver bridge, started from outside `swift test`.
// ROLE: test scaffolding -- a real BridgeServer, Session and channel with a fake reader edge, startable as a process.
// USED BY: server/tests/conformance/, whose Go tier launches it and drives it with the real MCP server binary.
// The driver starts it with `--transport`, reads one JSON line naming the endpoint from stdout, and closes stdin to stop it; nothing else goes to stdout.
// VoiceOver must not be involved: a CI runner has no VoiceOver session, no Accessibility grant and no capture voice.

import Fakes
import Foundation
import ScreenReaderWire
import VoiceOverBridgeAdapters
import VoiceOverBridgeDomain

/// Not a real macOS version, so an assertion cannot pass by matching a real one.
let readerVersion = "macOS 0.0.0-conformance"

let bridgeVersion = "0.0.0-conformance"

/// Keys are resolved spellings, since `vo` is expanded before the presser sees it; the probe entry uses the constant, and `vo+m` is a literal the Go driver repeats.
let harnessModifier = ModifierSetting.controlOption

/// An id this harness cannot classify answers itself, so the missing speech names it.
func resolved(_ gesture: String) -> String {
	guard let keystroke = try? CommandVocabulary.classify(gesture, readerModifier: harnessModifier)
	else { return gesture }
	return CommandVocabulary.identifier(for: keystroke)
}

let scriptedSpeech: [String: [String]] = [
	resolved(ReaderEdgeSetup.captureProbeKeystroke): [
		"conformance harness, the reader speaks"
	],
	resolved("vo+m"): [
		"conformance harness, text area",
		"one of two",
	],
]

func announce(endpoint: String) {
	let payload = ["endpoint": endpoint]
	guard let data = try? JSONSerialization.data(withJSONObject: payload),
		let line = String(data: data, encoding: .utf8)
	else {
		FileHandle.standardError.write(Data("could not encode the endpoint\n".utf8))
		exit(1)
	}
	// FileHandle, not `print`: `print` is fully buffered to a pipe, and the driver blocks on this line.
	FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

var transport = ""
var arguments = Array(CommandLine.arguments.dropFirst())
while let argument = arguments.first {
	arguments.removeFirst()
	switch argument {
	case "--transport":
		guard let value = arguments.first, ["local", "tcp"].contains(value) else {
			FileHandle.standardError.write(Data("--transport must be local or tcp\n".utf8))
			exit(2)
		}
		transport = value
		arguments.removeFirst()
	default:
		FileHandle.standardError.write(Data("unknown flag: \(argument)\n".utf8))
		exit(2)
	}
}
guard !transport.isEmpty else {
	FileHandle.standardError.write(Data("--transport is required\n".utf8))
	exit(2)
}

/// `/tmp` and a short name: a Unix socket path is at most 103 bytes, `NSTemporaryDirectory()` overruns it, and the kernel answers only `connect: invalid argument`.
let sandbox = "/tmp/vo-conf-\(UUID().uuidString.prefix(8))"
try? FileManager.default.createDirectory(
	atPath: sandbox, withIntermediateDirectories: true,
	attributes: [FileAttributeKey.posixPermissions: 0o700])

let config = FakeBridgeConfig()
switch transport {
case "tcp":
	config.connectionMode = .loopbackTcp
	// Port 0: the OS picks a free one, so parallel runs cannot collide.
	config.loopbackPort = 0
default:
	config.connectionMode = .localEndpoint
	// Its own name and home, so a run can neither collide with an installed bridge nor be answered by one.
	config.endpointName = "voMcpConformance"
}
// Unattended: a silence cap firing mid-run would change the answers the driver reads.
config.attended = false
config.cuesEnabled = false

// Built once for the process, so the scripted speech stays reachable from here.
let readerEdge = FakeAdapterFactory()

// Speech arrives as a consequence of the press, on the session's own thread, so the grace window is really tested.
readerEdge.readerModifier.setting = harnessModifier
readerEdge.keyPresser.onPress = { keystroke in
	for line in scriptedSpeech[CommandVocabulary.identifier(for: keystroke)] ?? [] {
		readerEdge.speechSource.emit(line, at: Date().timeIntervalSince1970)
	}
}

let server = BridgeServer(
	listener: Wiring.listener(
		config: config,
		dirs: LocalSocketDirs(runtimeDir: "", home: sandbox)
	),
	sessionFactory: { transport in
		Wiring.session(
			over: transport,
			clock: RealClock(),
			transcript: FileTranscript.session(in: sandbox),
			signals: FakeSessionSignals(),
			config: SessionConfig(
				readerVersion: readerVersion,
				attended: false,
				silenceCap: SilenceCapPolicy(enabled: false)
			),
			handlers: Registry.build(
				factory: readerEdge,
				readerVersion: readerVersion,
				bridgeVersion: bridgeVersion
			)
		)
	}
)

do {
	try server.start()
} catch {
	FileHandle.standardError.write(Data("could not listen: \(error)\n".utf8))
	exit(1)
}

guard let endpoint = server.status.endpoint else {
	server.stop()
	FileHandle.standardError.write(Data("the bridge started but reported no endpoint\n".utf8))
	exit(1)
}

/// Spelled the way the server's `--reader` flag wants it: `local:<name>` or `tcp:<host>:<port>`.
let spec: String
if transport == "tcp" {
	spec = "tcp:" + endpoint
} else {
	spec = "local:" + endpoint
}
announce(endpoint: spec)
FileHandle.standardError.write(
	Data("conformance bridge listening on \(endpoint); transcripts in \(sandbox)\n".utf8))

// Stdin EOF is the stop signal: unlike a signal, it cannot leave this process alive if the driver dies.
while let line = readLine(strippingNewline: false), !line.isEmpty {
	continue
}
server.stop()
try? FileManager.default.removeItem(atPath: sandbox)
exit(0)
