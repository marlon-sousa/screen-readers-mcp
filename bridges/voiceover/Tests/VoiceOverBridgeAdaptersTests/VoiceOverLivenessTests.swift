// Mirrors Sources/VoiceOverBridgeAdapters/VoiceOverLiveness.swift.

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
		let applications = FakeRunningApplications()
		#expect(liveness(applications: applications).readerIsRunning())
		#expect(applications.asked == ["com.apple.VoiceOver"])
	}

	@Test("THE IDENTIFIER IS EXACT, because a wrong one answers `not running` forever")
	func theIdentifierIsExact() {
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
		let tools = FakeProcessRunner()
		tools.failure = ProcessFailure("could not run /usr/bin/open")
		liveness(tools: tools).activate()
		#expect(tools.invocations.count == 1)
	}
}
