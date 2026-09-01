// ROLE: adapter -- IMPLEMENTS the ReaderLiveness domain port, over the
// AppleScriptRunner seam.
//
// BUILT BY: VoiceOverAdapterFactory. USED BY: the PressGesture handler, through
// the port, and only after a dispatch has already failed.
//
// IT ASKS THE NARROWEST QUESTION THAT SEPARATES TWO FAILURES. `return name` is
// an APPLICATION-level property: answering it needs the process, the AppleEvents
// grant and nothing else -- no scripting object model, no cursor, no window.
// That is precisely why spec 0041 could measure it still answering while every
// VoiceOver-specific call failed with `-1728`/`-1708`. Any richer probe would
// have failed too, and the two conditions would have looked identical again.
//
// SO THE PROBE MUST NOT BE "IMPROVED". Reading `last phrase`, or the cursor, or
// anything the reader has to consult its own object model for, would turn this
// into a second copy of the failing call rather than a control for it.
//
// AND SINCE 13.20 IT CAN START THE READER, WHICH IS THE OPPOSITE QUESTION ASKED
// BY A DIFFERENT CALLER. `ReaderEdgeSetup` asks BEFORE anything, because a
// session that is about to drive VoiceOver needs one running; when the probe
// says no it calls `activate()` and asks again.
//
// `activate()` GOES THROUGH A SECOND SEAM, AND THAT IS A REAL CHOICE. Launching
// an application is not an AppleScript question -- routing it through one would
// have meant reaching for a scripting term nobody here has measured, on a
// channel that by definition is not answering. So this class holds a
// ProcessRunner as well, and runs the command that WAS measured:
//
//   MEASURED 2026-08-31: `killall VoiceOver` does NOT relaunch the reader.
//   `open -a VoiceOver` does.
//
// That measurement is why `ReaderCondition`'s recoveries never say "restart
// VoiceOver" on their own: a human who followed a bare `killall` would be left
// with no screen reader. STARTING is all this does. A RESTART takes the reader
// away from somebody who is using it, and no handshake in this bridge may decide
// on one -- the failures name `readerRestartCommand` and a human runs it.
//
// IT SWALLOWS EVERY ERROR, WHICH IS THE PORT'S CONTRACT AND NOT LAZINESS: the
// question is a boolean, its one caller is already handling a failure, and every
// way this can fail -- the grant is gone, the reader is not running, the tool
// could not be launched -- is a "no" as far as that caller is concerned. What
// each of those MEANS is the gesture sender's business, and it has already said
// so by the time this is asked.

import VoiceOverBridgeDomain

public final class VoiceOverLiveness: ReaderLiveness {
	/// The probe itself, PUBLIC because a second reader asks the same question of
	/// a different thing and must not ask it in different words.
	///
	/// `TCCPermissionBroker` sends this script to find out whether the automation
	/// grant is in force, because on this bridge that grant is a fact about the
	/// CHANNEL rather than about the calling binary (13.11). It cannot go through
	/// this class: liveness collapses every failure into `false`, and the broker
	/// needs the NUMBER -- `-1743` is the missing grant and everything else is
	/// not. So the two share the script and not the interpretation, which is the
	/// same shape `captureVoiceIdentifierSuffix` already has: read a second time
	/// rather than copied, so a change to what is asked cannot reach one caller
	/// and miss the other.
	public static let readerNameScript = "tell application \"VoiceOver\" to return name"

	/// How the reader is started. `open` is what was measured to work; `killall`
	/// on its own is what was measured NOT to, and nothing here ever kills.
	public static let openTool = "/usr/bin/open"

	private let runner: any AppleScriptRunner
	private let tools: any ProcessRunner

	public init(runner: any AppleScriptRunner, tools: any ProcessRunner) {
		self.runner = runner
		self.tools = tools
	}

	public func readerAnswersItsOwnName() -> Bool {
		guard let name = try? runner.run(Self.readerNameScript) else {
			return false
		}
		// A REPLY IS THE ANSWER, NOT ITS CONTENTS. The name is localized like
		// every other string this reader produces, so comparing it with
		// "VoiceOver" would be a test that passes in English and fails in
		// Portuguese -- which is the lane's own no-reader-strings rule, and the
		// same trap `OSAScriptRunner` records for error messages. That it
		// answered AT ALL is the whole signal.
		return !name.isEmpty
	}

	/// Ask the system to start VoiceOver, and answer nothing.
	///
	/// `open` hands the launch to the launch services daemon and returns, so
	/// there is nothing here to report on -- the port says as much, and the only
	/// evidence that counts is `readerAnswersItsOwnName` afterwards. A failure to
	/// even run the tool is swallowed for the same reason every failure in this
	/// class is: the caller is about to ask the question that actually matters.
	public func activate() {
		_ = try? tools.run(Self.openTool, ["-a", "VoiceOver"])
	}
}
