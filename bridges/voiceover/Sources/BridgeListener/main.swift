// ROLE: a dev and live-tier LAUNCHER -- it starts the bridge listening, prints
// where, and runs until it is interrupted. It is not part of the shipped bundle.
//
// AN AMENDMENT TO SPEC 0046's 13.4 LAYOUT, with its why: the layout has no entry
// for it, and without it nothing outside a test can make this bridge listen --
// the control dialog that will is 13.10. An entry whose headline is "the bridge
// LISTENS" needs a way to see it listen that is not a unit test, and this repo's
// rule is that anything a check depends on is VERSIONED rather than improvised
// in a scratch directory (the 2026-08-22 rule). So it is here, reviewable, in
// thirty lines.
//
// IT IS A COMPOSITION ROOT'S CLIENT AND NOTHING ELSE. Every decision it makes is
// a command-line flag read into a BridgeConfig; the graph is Wiring's. If logic
// starts accumulating here, it belongs in Wiring or in the dialog.
//
// NOT IN THE .app, deliberately: build.sh assembles the shipped bundle and does
// not copy this. `swift build --product BridgeListener` is how you get it.
//
// Usage:
//   BridgeListener [--tcp [port]] [--endpoint <name-or-path>] [--unattended]

import Foundation
import VoiceOverBridgeAdapters
import VoiceOverBridgeDomain

/// The launcher's own settings object: an in-memory BridgeConfig, because there
/// is no persisted one until 13.10 gives the dialog something to persist.
final class LaunchConfig: BridgeConfig {
	var connectionMode: ConnectionMode = .default
	var endpointName: String = defaultEndpointName
	var loopbackPort: Int = defaultLoopbackPort
	var attended: Bool = true
}

/// Cues printed rather than played: this launcher is run from a terminal by
/// somebody watching it, and the real macOS cue adapter is 13.10's.
final class PrintingSignals: SessionSignals {
	func sessionStarted(persona: String) {
		print("session started (persona: \(persona.isEmpty ? "-" : persona))")
	}

	func sessionEnded() {
		print("session ended")
	}
}

let config = LaunchConfig()
var arguments = Array(CommandLine.arguments.dropFirst())
while let argument = arguments.first {
	arguments.removeFirst()
	switch argument {
	case "--tcp":
		config.connectionMode = .loopbackTcp
		if let next = arguments.first, let port = Int(next) {
			config.loopbackPort = port
			arguments.removeFirst()
		}
	case "--endpoint":
		guard let name = arguments.first else {
			FileHandle.standardError.write(Data("--endpoint needs a name or a path\n".utf8))
			exit(2)
		}
		config.endpointName = name
		arguments.removeFirst()
	case "--unattended":
		config.attended = false
	default:
		FileHandle.standardError.write(Data("unknown flag: \(argument)\n".utf8))
		exit(2)
	}
}

let bus = SimpleEventBus()
_ = bus.subscribe { event in
	if case .serverStatus(let status) = event {
		print("server: \(status.state.rawValue)\(status.endpoint.map { " on \($0)" } ?? "")")
	}
}
let server = Wiring.bridgeServer(config: config, signals: PrintingSignals(), eventBus: bus)

// Interrupt has to reach the accept loop, and the handler runs on a queue rather
// than in the signal context: stop() takes a lock and waits on a thread, neither
// of which is async-signal-safe. `signal(SIGINT, SIG_IGN)` is what stops the
// default handler from killing the process before the source fires.
signal(SIGINT, SIG_IGN)
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
interrupt.setEventHandler {
	print("stopping")
	server.stop()
	exit(0)
}
interrupt.resume()

do {
	try server.start()
} catch {
	FileHandle.standardError.write(Data("could not listen: \(error)\n".utf8))
	exit(1)
}
print("listening. ^C to stop.")
dispatchMain()
