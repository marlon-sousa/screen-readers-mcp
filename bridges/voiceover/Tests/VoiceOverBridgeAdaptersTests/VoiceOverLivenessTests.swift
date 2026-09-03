// Mirrors Sources/VoiceOverBridgeAdapters/VoiceOverLiveness.swift.
//
// WHAT IS UNDER TEST CHANGED WITH 13.26, AND THE OLD TESTS ARE THE RECORD OF WHY.
// Until then the question "is the reader there" was an AppleEvent -- `tell
// application "VoiceOver" to return name` -- chosen because an application-level
// property answers when the scripting object model is dead (spec 0041). It
// worked, and it cost a PERMISSION the session might have had no other use for,
// on a machine that intended to drive the reader entirely by keystrokes.
//
// So the question is now the running-application list, which costs nothing and
// cannot be switched off. Two properties matter here and both have a test: the
// IDENTIFIER it asks about (case-sensitive, and a wrong one answers "not running"
// forever), and that starting the reader is still `open` and never `killall`.

import Fakes
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("VoiceOverLiveness")
struct VoiceOverLivenessTests {
	private func liveness(
		applications: FakeRunningApplications = FakeRunningApplications(),
		tools: FakeProcessRunner = FakeProcessRunner()
	) -> VoiceOverLiveness {
		VoiceOverLiveness(applications: applications, tools: tools)
	}

	@Test("IT ASKS THE RUNNING-APPLICATION LIST, and sends no AppleEvent at all")
	func itAsksTheWorkspace() {
		// The whole of 13.26 in one assertion: this question no longer costs a
		// grant, so a machine that has never granted Automation -- and has the
		// AppleScript switch off, which is where a careful VoiceOver user should
		// be able to leave it -- can still have its reader confirmed.
		let applications = FakeRunningApplications()
		#expect(liveness(applications: applications).readerIsRunning())
		#expect(applications.asked == ["com.apple.VoiceOver"])
	}

	@Test("THE IDENTIFIER IS EXACT, because a wrong one answers `not running` forever")
	func theIdentifierIsExact() {
		// Measured 2026-09-02: `com.apple.VoiceOver` finds the reader and
		// `com.apple.voiceover` returns an empty list with NO error. So a typo here
		// would report a dead reader on a healthy machine, permanently and
		// silently -- and it would look exactly like the condition rung 2 exists to
		// report. The spelling was read out of the app's own Info.plist.
		#expect(VoiceOverLiveness.readerBundleIdentifier == "com.apple.VoiceOver")
		let elsewhere = FakeRunningApplications(running: ["com.apple.voiceover"])
		#expect(!liveness(applications: elsewhere).readerIsRunning())
	}

	@Test("a machine where it is not running says so")
	func notRunningSaysSo() {
		#expect(!liveness(applications: FakeRunningApplications(running: [])).readerIsRunning())
	}

	@Test("activating the reader OPENS it, and never kills it")
	func activationOpensTheReader() {
		// MEASURED 2026-08-31: `killall VoiceOver` does NOT relaunch the reader --
		// it leaves a blind person with no screen reader at all -- and
		// `open -a VoiceOver` does. This asserts the command that was measured, and
		// asserts the absence of the one that was measured not to work, because
		// getting it wrong here is the most expensive mistake in this file.
		let tools = FakeProcessRunner()
		liveness(tools: tools).activate()
		#expect(
			tools.invocations == [
				FakeProcessRunner.Invocation(
					executable: "/usr/bin/open", arguments: ["-a", "VoiceOver"], stdin: nil)
			])
	}

	@Test("a tool that will not run is swallowed, because the re-check is the evidence")
	func activationSwallowsItsFailures() {
		// The port answers nothing on purpose: `open` hands the launch to the
		// system and returns, so there is nothing here to report on. A failure to
		// even launch the tool is a "no" that `readerIsRunning` will give a moment
		// later, in the words its caller already handles.
		let tools = FakeProcessRunner()
		tools.failure = ProcessFailure("could not run /usr/bin/open")
		liveness(tools: tools).activate()
		#expect(tools.invocations.count == 1)
	}

	@Test("the name script is KEPT, for the one caller that is asking about AppleEvents")
	func theNameScriptSurvivesForTheBroker() {
		// It stopped being this class's probe and did not stop existing:
		// `TCCPermissionBroker` sends it to learn whether the AUTOMATION GRANT is in
		// force, because on this bridge that grant is a fact about the CHANNEL
		// rather than about the calling binary. Asserted here so that a tidy-up
		// which deletes an unused constant has to read this sentence first.
		#expect(
			VoiceOverLiveness.readerNameScript
				== "tell application \"VoiceOver\" to return name")
	}
}
