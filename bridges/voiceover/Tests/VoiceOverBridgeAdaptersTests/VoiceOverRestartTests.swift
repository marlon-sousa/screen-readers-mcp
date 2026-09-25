// Mirrors Sources/VoiceOverBridgeAdapters/VoiceOverRestart.swift.

import Fakes
import Testing
import VoiceOverBridgeDomain

@testable import VoiceOverBridgeAdapters

@Suite("VoiceOverRestart")
struct VoiceOverRestartTests {
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
		let (tools, _, restart) = machine(quitWorks: false)
		do {
			try restart.restart()
			Issue.record("expected the quit to fail")
		} catch let failure as ReaderRestartError {
			#expect(failure.readerStillRunning)
			#expect(failure.description.contains("still running"))
			#expect(!tools.invocations.contains { $0.executable == VoiceOverRestart.openTool })
		} catch {
			Issue.record("expected a ReaderRestartError")
		}
	}

	@Test("a reader that does not COME BACK says so in the loudest terms available")
	func aReaderThatDoesNotComeBack() {
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
		#expect(tools.invocations.map(\.executable) == [VoiceOverRestart.openTool])
	}

	@Test("it starts the reader the same way liveness does -- one route, not two")
	func oneWayToStartThisReader() {
		#expect(VoiceOverRestart.openTool == VoiceOverLiveness.openTool)
	}
}
