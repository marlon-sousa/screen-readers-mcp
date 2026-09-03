// Mirrors Sources/VoiceOverBridgeAdapters/VoiceOverRestart.swift.
//
// THE SEQUENCE IS THE WHOLE CLASS, AND THE ORDER IS WHAT IS UNDER TEST. This
// repository printed `killall VoiceOver && open -a VoiceOver` as advice for
// weeks, and it is wrong in two independent ways -- `killall` alone does not
// bring the reader back, and the `&&` races, because `killall` returns when the
// SIGNAL IS SENT and `open` on an application the system still believes is
// running does nothing at all. Both cost the maintainer real time, and the second
// very probably cost the 2026-09-02 field report twenty minutes and an
// interruption of the blind user at the machine.
//
// So the assertions are about a WAIT between two commands, and about which half
// failed -- because "I could not stop VoiceOver" and "I stopped VoiceOver and it
// did not come back" are opposite sentences to say to a person who may be sitting
// in silence.

import Fakes
import Testing
import VoiceOverBridgeDomain

@testable import VoiceOverBridgeAdapters

@Suite("VoiceOverRestart")
struct VoiceOverRestartTests {
	/// A machine whose reader really does go away and come back when the tools are
	/// run -- which is what makes the ORDER assertable rather than the call count.
	private func machine(
		quitWorks: Bool = true, startWorks: Bool = true
	) -> (FakeProcessRunner, FakeRunningApplications, VoiceOverRestart) {
		let tools = FakeProcessRunner()
		let apps = FakeRunningApplications(running: [VoiceOverLiveness.readerBundleIdentifier])
		tools.beforeRun = { executable, _ in
			if executable == VoiceOverRestart.killTool, quitWorks {
				apps.running.remove(VoiceOverLiveness.readerBundleIdentifier)
			}
			if executable == VoiceOverRestart.openTool, startWorks {
				apps.running.insert(VoiceOverLiveness.readerBundleIdentifier)
			}
		}
		return (tools, apps, VoiceOverRestart(tools: tools, applications: apps, clock: FakeClock()))
	}

	@Test("it quits, then starts -- in that order, and never as one command")
	func itQuitsThenStarts() throws {
		let (tools, apps, restart) = machine()
		try restart.restart()
		#expect(tools.invocations.map(\.executable) == [VoiceOverRestart.killTool, VoiceOverRestart.openTool])
		#expect(tools.invocations.first?.arguments == ["VoiceOver"])
		#expect(tools.invocations.last?.arguments == ["-a", "VoiceOver"])
		#expect(apps.isRunning(bundleIdentifier: VoiceOverLiveness.readerBundleIdentifier))
	}

	@Test("it does NOT start until the process is actually gone")
	func itWaitsForTheProcessToGo() throws {
		// THE `&&` BUG, AS A TEST. `killall` returns on the SIGNAL, not on the exit,
		// so a reader that takes a moment to die must not be `open`ed while the
		// system still believes it is running -- which does nothing at all and
		// leaves somebody with no screen reader. The fake dies on the third poll.
		let tools = FakeProcessRunner()
		let apps = FakeRunningApplications()
		var dying = false
		var pollsWhileDying = 0
		var stillRunningWhenOpened: Bool?
		apps.beforeAsk = {
			guard dying else { return }
			pollsWhileDying += 1
			if pollsWhileDying >= 3 { apps.running.remove(VoiceOverLiveness.readerBundleIdentifier) }
		}
		tools.beforeRun = { executable, _ in
			if executable == VoiceOverRestart.killTool { dying = true }
			if executable == VoiceOverRestart.openTool {
				dying = false
				stillRunningWhenOpened = apps.running.contains(VoiceOverLiveness.readerBundleIdentifier)
				apps.running.insert(VoiceOverLiveness.readerBundleIdentifier)
			}
		}
		try VoiceOverRestart(tools: tools, applications: apps, clock: FakeClock()).restart()
		#expect(stillRunningWhenOpened == false)
		#expect(pollsWhileDying >= 3)
	}

	@Test("a reader that will not quit leaves everything alone, and SAYS it is still running")
	func aReaderThatWillNotQuit() {
		// The safe failure: their screen reader still works, and nothing was
		// started, so nothing is half done.
		let (tools, _, restart) = machine(quitWorks: false)
		do {
			try restart.restart()
			Issue.record("expected the quit to fail")
		} catch let failure as ReaderRestartError {
			#expect(failure.readerStillRunning)
			#expect(failure.description.contains("still running"))
			// AND `open` WAS NEVER RUN. A restart that could not stop the reader must
			// not go on to start a second one.
			#expect(!tools.invocations.contains { $0.executable == VoiceOverRestart.openTool })
		} catch {
			Issue.record("expected a ReaderRestartError")
		}
	}

	@Test("a reader that does not COME BACK says so in the loudest terms available")
	func aReaderThatDoesNotComeBack() {
		// The dangerous failure, and the one this whole class exists to be honest
		// about: there is a person with no screen reader, right now.
		let (_, _, restart) = machine(startWorks: false)
		do {
			try restart.restart()
			Issue.record("expected the start to fail")
		} catch let failure as ReaderRestartError {
			#expect(!failure.readerStillRunning)
			#expect(failure.description.contains("THE READER IS NOT RUNNING"))
			#expect(failure.description.contains("Command-F5"))
		} catch {
			Issue.record("expected a ReaderRestartError")
		}
	}

	@Test("a reader that was not running is simply started")
	func aStoppedReaderIsJustStarted() throws {
		let tools = FakeProcessRunner()
		let apps = FakeRunningApplications(running: [])
		tools.beforeRun = { executable, _ in
			if executable == VoiceOverRestart.openTool {
				apps.running.insert(VoiceOverLiveness.readerBundleIdentifier)
			}
		}
		try VoiceOverRestart(tools: tools, applications: apps, clock: FakeClock()).restart()
		// NOTHING WAS KILLED. Sending a kill to a reader that is not there is
		// harmless and pointless, and skipping it keeps the log honest about what
		// this bridge did to somebody's machine.
		#expect(tools.invocations.map(\.executable) == [VoiceOverRestart.openTool])
	}

	@Test("it starts the reader the same way liveness does -- one route, not two")
	func oneWayToStartThisReader() {
		#expect(VoiceOverRestart.openTool == VoiceOverLiveness.openTool)
	}
}
