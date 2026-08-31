// A REAL VoiceOver bridge, started from outside `swift test`.
//
// ROLE: test scaffolding (a builder, not a port double), and the Swift twin of
// bridges/nvda/tests/support/conformance_bridge.py. It is a real BridgeServer, a
// real listener, a real Session, a real JsonLinesChannel and a real Registry,
// with a FAKE reader edge in place of VoiceOver -- made STARTABLE AS A PROCESS so
// something other than `swift test` can drive it.
// USED BY: server/tests/conformance/, whose Go tier launches this and then drives
// it with the real MCP server binary.
//
// WHY IT EXISTS, AND IT IS THE SAME ARGUMENT THE PYTHON ONE MAKES. Every other
// test of the Go server drives a Go fake bridge, which encodes frames with the
// same generated binding the server decodes them with -- so a bug IN THE BINDING
// is invisible there: both sides would be wrong together, in agreement. The wire
// contract has THREE bindings (generated Go, hand-written Python, hand-written
// Swift) and until 13.11 only two of them had ever exchanged a byte with each
// other. `scripts/drift.py --swift` checks this binding against the schema by
// reading its source; it cannot check that what it EMITS is what the server
// PARSES. That is what this makes possible, and it is the first time the two
// halves of this lane are gated together.
//
// THE PROTOCOL WITH ITS DRIVER IS DELIBERATELY TINY, because the driver is in
// another language and has to implement it: start us with `--transport`, read ONE
// JSON line from stdout naming the endpoint we are listening on, then close our
// stdin to stop us. Nothing else is ever written to stdout. It is byte-for-byte
// the same handshake the Python harness uses, so the Go side has one driver
// rather than two.
//
// VOICEOVER IS NOT INVOLVED AND MUST NOT BE. What is under test is the WIRE, not
// the reader -- so every adapter that would touch the machine is a fake, and that
// is not merely convenient. This runs in CI on a hosted macOS runner with no
// VoiceOver session, no Accessibility grant and no capture voice installed; a
// harness that reached for any of them would fail there for reasons that have
// nothing to do with the contract. It is also what keeps the run safe on a
// developer's own machine: nothing here selects a voice, raises a consent dialog,
// types into a window or speaks out loud.
//
// KEEP IT THIN. The graph is Wiring's. Logic that starts accumulating here
// belongs in Wiring or in the scenario that drives it.

import Fakes
import Foundation
import ScreenReaderWire
import VoiceOverBridgeAdapters
import VoiceOverBridgeDomain

/// The reader version this harness announces.
///
/// NOT A REAL macOS VERSION, and deliberately recognisable: an assertion that
/// matched a real one by accident -- on the very machine where a real VoiceOver
/// is also running -- would be a false pass. The Python harness's
/// `2026.1.0-conformance` makes the same choice for the same reason.
let readerVersion = "macOS 0.0.0-conformance"

/// This harness's own bridge version, equally recognisable.
let bridgeVersion = "0.0.0-conformance"

/// The fake reader's script: pressing this command makes it "speak" these lines,
/// through the REAL speech buffer, exactly as a real press would.
///
/// It is what lets the driver prove a whole "press, then read what it said" round
/// trip across the language boundary -- indices, ranges and all -- with no reader
/// on the machine.
let scriptedSpeech: [String: [String]] = [
	"describe item in voiceover cursor": [
		"conformance harness, text area",
		"one of two",
	]
]

/// One line of JSON on stdout, then silence.
func announce(endpoint: String) {
	let payload = ["endpoint": endpoint]
	guard let data = try? JSONSerialization.data(withJSONObject: payload),
		let line = String(data: data, encoding: .utf8)
	else {
		FileHandle.standardError.write(Data("could not encode the endpoint\n".utf8))
		exit(1)
	}
	// Written with FileHandle rather than `print` because the driver BLOCKS on
	// this line and our stdout is a pipe: Swift's `print` is fully buffered to a
	// pipe, so a `print` here would deadlock the Go side until we exited. Measured
	// on this repo's own launcher, whose startup report was invisible for exactly
	// this reason.
	FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

// -- arguments ---------------------------------------------------------------

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

// -- the endpoint nothing else owns ------------------------------------------

/// A home directory of this run's own, so the local endpoint cannot collide with
/// a real bridge the developer has listening -- and cannot be SATISFIED by one,
/// which is the more dangerous of the two. The integration scenarios in this
/// package invent a directory under /tmp for exactly the same reason.
///
/// `/tmp` AND A SHORT NAME, NOT `NSTemporaryDirectory()`, and that is a hard
/// constraint rather than a preference: a Unix socket path may be at most 103
/// bytes (`LocalSocketPath` on both sides enforces it), and macOS's per-user
/// temporary directory is a generated `/var/folders/...` path around 49 bytes
/// before anything of ours is appended. Adding a UUID and
/// `/.screenreader-mcp/<name>.sock` to that overruns the limit, and the kernel's
/// own answer to a long path is `connect: invalid argument`, which names neither
/// the limit nor the path.
let sandbox = "/tmp/vo-conf-\(UUID().uuidString.prefix(8))"
try? FileManager.default.createDirectory(
	atPath: sandbox, withIntermediateDirectories: true,
	attributes: [FileAttributeKey.posixPermissions: 0o700])

let config = FakeBridgeConfig()
switch transport {
case "tcp":
	config.connectionMode = .loopbackTcp
	// Port 0: the OS picks a free one, so parallel runs cannot collide. The
	// Python harness does the same.
	config.loopbackPort = 0
default:
	config.connectionMode = .localEndpoint
	// Carries this harness's own name as well as its own home, so a run can
	// neither collide with an installed bridge nor be answered by one. Kept short
	// for the path-length reason above.
	config.endpointName = "voMcpConformance"
}
// UNATTENDED: nobody is sitting at a CI runner, and a silence cap that fired
// mid-run would change the answers the driver is reading.
config.attended = false
config.cuesEnabled = false

// -- the bridge, with a fake reader behind it --------------------------------

// The fake reader edge, built ONCE for the process rather than per session: the
// driver opens one session at a time, and a factory that rebuilt its doubles per
// connection would make the scripted speech unreachable from out here.
let readerEdge = FakeAdapterFactory()

// Speech arrives as a CONSEQUENCE of the command, on the session's own thread,
// which is what makes the grace window a real thing to test rather than a buffer
// that was already full. It is the whole reason a "press, then read what it said"
// round trip can be proved across the language boundary with no reader present.
readerEdge.gestureSender.onPress = { command in
	for line in scriptedSpeech[command] ?? [] {
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

/// The accepting endpoint, spelled the way the SERVER's `--reader` flag wants it.
///
/// The bridge reports a path or a `host:port`; the server wants `local:<name>` or
/// `tcp:<host>:<port>`. Translating here keeps the driver from having to know
/// either spelling -- the same division of labour the Python harness makes.
let spec: String
if transport == "tcp" {
	spec = "tcp:" + endpoint
} else {
	spec = "local:" + endpoint
}
announce(endpoint: spec)
FileHandle.standardError.write(
	Data("conformance bridge listening on \(endpoint); transcripts in \(sandbox)\n".utf8))

// Stdin EOF is the stop signal, rather than a signal handler: the driver closing
// our stdin works identically on every platform, and it cannot leave us alive if
// the driver dies -- which a kill sent to an intermediate launcher process could.
while let line = readLine(strippingNewline: false), !line.isEmpty {
	continue
}
server.stop()
try? FileManager.default.removeItem(atPath: sandbox)
exit(0)
