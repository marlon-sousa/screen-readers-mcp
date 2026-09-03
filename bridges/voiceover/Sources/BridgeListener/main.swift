// ROLE: a dev and live-tier LAUNCHER -- it starts the bridge listening, prints
// where, and runs until it is interrupted. It is not part of the shipped bundle.
//
// AN AMENDMENT TO SPEC 0046's 13.4 LAYOUT, with its why: the layout has no entry
// for it, and without it nothing outside a test can make this bridge listen --
// the control dialog that will is a later entry, deferred on 2026-08-30 until the
// bridge can drive VoiceOver over its own window. An entry whose headline is "the
// bridge LISTENS" needs a way to see it listen that is not a unit test, and this
// repo's rule is that anything a check depends on is VERSIONED rather than
// improvised in a scratch directory (the 2026-08-22 rule). So it is here,
// reviewable, and it is what STARTS A BRIDGE on this platform today.
//
// IT IS A COMPOSITION ROOT'S CLIENT AND NOTHING ELSE. Every decision it makes is
// a command-line flag read into a BridgeConfig; the graph is Wiring's. If logic
// starts accumulating here, it belongs in Wiring or in the dialog.
//
// NOT IN THE .app, deliberately: build.sh assembles the shipped bundle and does
// not copy this. `swift build --product BridgeListener` is how you get it.
//
// IT READS THE PERSISTED SETTINGS AND LETS FLAGS OVERRIDE THEM (13.10). Until
// there is a dialog, the stored preferences are the only place a machine's
// choices can live -- so this launcher starts from them and every flag below wins
// over what is stored, which keeps an invocation reproducible from its own
// command line while a machine that has been configured stays configured.
//
// AND IT SAYS WHAT THE MACHINE CAN DO BEFORE ANYTHING IS PRESSED. The capture
// voice's state and the one permission this bridge needs: two answers that decide
// whether a run is going to work, printed at startup rather than discovered as a
// failure ten commands in. NEITHER ASKS A HUMAN FOR ANYTHING -- `status` shows no
// dialog, which is what makes them safe to print on a machine nobody is sitting
// at.
//
// IT PRINTED TWO MORE ROWS UNTIL 13.31, AND THIS HEADER WENT ON ADVERTISING THEM.
// One was VoiceOver's own "Allow VoiceOver to be controlled with AppleScript"
// switch; the other was the Automation grant, which 13.11 taught this launcher to
// read by USING the channel rather than by asking about this binary -- which is
// why the header said the permission rows cost a subprocess. Both went with the
// AppleScript channel (spec 0055), the code block below has said so since, and the
// header had not. It says so now.
//
// Usage:
//   BridgeListener [--tcp [port]] [--endpoint <name-or-path>] [--unattended]
//                  [--print-cues]

import AppKit
import Foundation
import VoiceOverBridgeAdapters
import VoiceOverBridgeDomain

// STDOUT IS UNBUFFERED, AND THIS ONE LINE COST AN EVENING'S CONFUSION.
//
// Swift's `print` is BLOCK-buffered when stdout is not a terminal, so every line
// below -- the endpoint, the capture voice's state, the permission rows -- is
// invisible for as long as this process runs if you redirect it to a file or a
// pipe. Which is exactly what a live check does: `BridgeListener > run.log &`,
// and then nothing to read while you wonder whether it started.
//
// THE WORKAROUND SOMEBODY WILL REACH FOR IS WORSE THAN THE PROBLEM. Running this
// under `script(1)` to get a pty does make the output appear -- and it also
// breaks the accessibility reads: measured 2026-08-31, `getFocusInfo` answered
// `-25204 kAXErrorCannotComplete` for every application under `script -q`, and
// the same build launched directly answered `AXList / com.apple.finder`
// immediately. An hour went into suspecting the bridge, `NSWorkspace`, the SSH
// session and a wedged Finder before the harness turned out to be the variable.
// So the buffering is fixed here, where it belongs, rather than worked around
// where it bites.
setbuf(stdout, nil)

// ============================================================================
// THIS LAUNCHER IS AN NSApplication, AND UNTIL 13.33 IT WAS NOT -- WHICH KILLED
// EVERY SESSION THAT ASKED A HUMAN A QUESTION.
// ============================================================================
//
// It used to end with `dispatchMain()`, which parks the main thread BY EXITING
// IT. AppKit needs a real main run loop, so the first `askUser` -- whose window
// `AppKitPromptWindow` schedules with `DispatchQueue.main.async` -- was scheduled
// onto a run loop that was not there. The process died with SIGILL (exit 132),
// preceded by *"Attempting to add timer to main runloop, but the main thread has
// exited"*.
//
// WHAT IT COST IS MORE THAN A CRASH, and it is why board entry 13.33 is bundled
// with 13.24 and 13.32 rather than filed on its own: a session that dies here
// dies WITHOUT TEARING DOWN, so the capture voice is left selected on somebody's
// machine. That is 13.23's hazard reached by a dev tool, and it is how 13.32's
// finding was produced in the first place.
//
// IT WAS PRE-EXISTING AND NOT CAUSED BY 13.31, which was checked rather than
// assumed: `main` was built in a git worktree as a control on 2026-09-03 and
// crashes identically. What hid it for this long is that `askUser` is reached
// only by `poe live`, whose script asks its question LAST and prints its closing
// summary before the process dies.
//
// AND IT DOES NOT PRE-EMPT 13.14. That entry gives the SHIPPED BUNDLE a control
// dialog wired through `Wiring.controlSurface`; this file is a dev launcher
// `build.sh` deliberately does not copy into the bundle. Borrowing AppKit's run
// loop is not designing a UI, and the alternative -- making `UserPrompter`
// unreachable from here and refusing by name -- would make half of 13.10's human
// channel unexercisable against a real reader until 13.14 lands, for the
// privilege of making a working feature not work.
//
// `.accessory`: no Dock icon and no menu bar, which is what a launcher wants.
// `NSApp.activate(ignoringOtherApps:)` in `AppKitPromptWindow`'s panel still
// brings the question to the front from an accessory app.
//
// CREATED HERE, ON THE MAIN THREAD, BEFORE ANYTHING CAN SCHEDULE ONTO IT.
// `NSApplication.shared` is main-thread-only, and the session runs on a
// background thread from the moment the server starts.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

/// The launcher's settings: whatever is stored, with this run's flags on top.
///
/// IT IS A DECORATOR RATHER THAN A COPY, so a flag overrides for THIS run and
/// changes nothing on the machine: reading falls through to the stored value
/// unless this invocation said otherwise, and nothing here writes. That is what
/// keeps a live check reproducible from its own command line -- the 2026-08-22
/// rule's spirit -- while a machine somebody has configured stays configured.
final class LaunchConfig: BridgeConfig {
	private let stored: any BridgeConfig
	private var modeOverride: ConnectionMode?
	private var nameOverride: String?
	private var portOverride: Int?
	private var attendedOverride: Bool?

	init(stored: any BridgeConfig) {
		self.stored = stored
	}

	var connectionMode: ConnectionMode {
		get { modeOverride ?? stored.connectionMode }
		set { modeOverride = newValue }
	}

	var endpointName: String {
		get { nameOverride ?? stored.endpointName }
		set { nameOverride = newValue }
	}

	var loopbackPort: Int {
		get { portOverride ?? stored.loopbackPort }
		set { portOverride = newValue }
	}

	var attended: Bool {
		get { attendedOverride ?? stored.attended }
		set { attendedOverride = newValue }
	}

	/// Not overridable from the command line: whether the machine plays its cues
	/// is a fact about the ROOM, and a flag that silenced them for one run would
	/// be an agent-shaped decision about what a person hears.
	var cuesEnabled: Bool {
		get { stored.cuesEnabled }
		set { stored.cuesEnabled = newValue }
	}
}

/// The real cues, with a line in the terminal beside each one.
///
/// BOTH, AND NEITHER IS DECORATION. The tones and the spoken persona are for the
/// person at the machine -- they are the signal that something has taken their
/// screen reader -- and the printed line is for whoever is watching the terminal,
/// who can scroll back. `--print-cues` drops the audible half for a developer
/// working in a room with other people; the preference that silences it for good
/// is the machine's own `cuesEnabled`.
final class ReportingSignals: SessionSignals {
	private let audible: (any SessionSignals)?

	init(audible: (any SessionSignals)?) {
		self.audible = audible
	}

	func sessionStarted(persona: String) throws {
		print("session started (persona: \(persona.isEmpty ? "-" : persona))")
		try audible?.sessionStarted(persona: persona)
	}

	func sessionEnded() throws {
		print("session ended")
		try audible?.sessionEnded()
	}

	func silenceWarning() throws {
		print("SILENCE CAP: the human has not heard their machine for a while")
		try audible?.silenceWarning()
	}

	func silenceLifted() throws {
		print("SILENCE CAP: LIFTED -- the machine is audible again")
		try audible?.silenceLifted()
	}

	func silenceResuppressed() throws {
		print("SILENCE CAP: RE-ARMED -- the machine is quiet again, on a fresh window")
		try audible?.silenceResuppressed()
	}
}

let config = LaunchConfig(stored: Wiring.bridgeConfig())
var playCues = true
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
	case "--print-cues":
		playCues = false
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
let server = Wiring.bridgeServer(
	config: config,
	signals: ReportingSignals(audible: playCues ? Wiring.sessionSignals(config: config) : nil),
	eventBus: bus
)

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
// Where captured speech is read from, printed because a live run's first
// question when nothing comes back is which file the bridge is watching --
// and the answer is a value Wiring resolved, not a decision made here.
print("reading speech from \(Wiring.capturePath())")
// And where it TELLS the capture voice what to do, for the same reason: a live
// run's second question, when the machine does not go quiet, is which file the
// extension is reading.
print("writing capture mode to \(Wiring.markerPath())")
// What the machine says about the capture voice right now, so a run that is
// going to fail says so before a human starts pressing keys -- by name, with the
// recovery, which is the whole point of ProviderState.
print("capture voice: \(Wiring.providerLifecycle().state().report)")
// The permission, READ and never requested: `status` shows no dialog, which is
// what makes it safe to print on a machine nobody is sitting at. The three things
// that ask for it are `typeText`, `pressGesture` and nothing else -- both post
// system events, which since 13.31 is the only way this bridge drives the reader
// at all.
//
// THIS BLOCK USED TO PRINT TWO MORE ROWS, AND BOTH WENT WITH THE APPLESCRIPT
// CHANNEL AT 13.31. One was VoiceOver's own "Allow VoiceOver to be controlled with
// AppleScript" switch, printed as a PRECONDITION because it was observable,
// unsettable by this bridge and required; the other was the Automation grant,
// which 13.11 had to teach this launcher to read by USING the channel rather than
// by asking about this binary (measured 2026-08-30: it printed `not granted` one
// minute after this very process had driven the reader through a whole MCP
// session). Neither is required now, so printing either would send a human to
// change a setting that cannot affect anything. Spec 0055.
let broker = Wiring.permissionBroker()
for permission in Permission.allCases {
	switch broker.status(of: permission) {
	case .granted:
		print("permission \(permission.rawValue): granted")
	case .notGranted:
		print("permission \(permission.rawValue): NOT GRANTED -- \(permission.recovery)")
	}
}
// AND THIS IS WHERE `dispatchMain()` USED TO BE. Both park the main thread
// forever; only one of them leaves a RUN LOOP on it, which is what every window
// this bridge opens is scheduled against. See the block at the top of this file
// for what the difference cost.
application.run()
