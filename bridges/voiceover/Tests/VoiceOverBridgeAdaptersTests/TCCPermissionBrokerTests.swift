// Mirrors Sources/VoiceOverBridgeAdapters/TCCPermissionBroker.swift.
//
// IT EXERCISES `status(.automationVoiceOver)` AND NOTHING ELSE, and the omissions
// are the point of the file rather than gaps in it:
//
//   * `request` MAY NEVER BE CALLED FROM A TEST. It raises a real system consent
//     dialog on the developer's own machine and leaves the process on a list that
//     STAYS granted, with no undo -- a test that reached it would permanently
//     change the machine it ran on, which is exactly what the Accessibility
//     lever exists to keep deliberate.
//   * `status(.accessibility)` and `isTrusted()` read the real
//     `AXIsProcessTrusted`. There is no seam under them and there should not be:
//     they are a leaf's worth of code with nothing to decide.
//
// WHAT IS LEFT IS THE DECISION 13.11 MOVED UP OUT OF THE LEAF: which AppleScript
// error numbers mean the automation grant is missing, and which mean the question
// could not be answered at all. That distinction is the whole fix -- 13.10 read
// this permission with an API that answers about the CALLING BINARY, and the
// bridge sends every AppleEvent from an `osascript` subprocess, so the row
// printed a confident false negative on a machine that was working (measured
// 2026-08-30: -1744 from the API, a successful reader reply from the channel,
// seconds apart).
//
// THE NUMBERS ARE READ FROM THE ADAPTERS THAT OWN THEM rather than spelled again
// here. A test that wrote `-1743` as a literal would go on passing after somebody
// changed the constant, which is the one failure a drift test exists to prevent.

import Fakes
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("TCCPermissionBroker")
struct TCCPermissionBrokerTests {
	@Test("it asks the CHANNEL, with the same probe the liveness check sends")
	func itAsksTheChannel() throws {
		let runner = FakeAppleScriptRunner()
		runner.defaultAnswer = "VoiceOver"

		_ = TCCPermissionBroker(scripts: runner).status(of: .automationVoiceOver)

		// The same script, not merely a similar one. Reading a permission down a
		// different route than the events travel would answer about a route
		// nothing uses -- which is the shape of the bug this replaced.
		let script = try #require(runner.scripts.first)
		#expect(script == VoiceOverLiveness.readerNameScript)
	}

	@Test("a reply means the grant is held, whoever actually holds it")
	func aReplyMeansGranted() {
		// The measured case: the grant belongs to the RESPONSIBLE process, which
		// on the maintainer's machine was the SSH session rather than this binary.
		// The channel answering is the only evidence that matters, and it is
		// evidence about the events the bridge will really send.
		let runner = FakeAppleScriptRunner()
		runner.defaultAnswer = "VoiceOver"
		#expect(TCCPermissionBroker(scripts: runner).status(of: .automationVoiceOver) == .granted)
	}

	@Test("an answer in ANY language counts, because the reader's name is localized")
	func anyReplyCounts() {
		// The lane's no-reader-strings rule. `VoiceOverLiveness` makes the same
		// assertion for the same probe; both would break together if either
		// started comparing the text.
		let runner = FakeAppleScriptRunner()
		runner.defaultAnswer = "Voz Over"
		#expect(TCCPermissionBroker(scripts: runner).status(of: .automationVoiceOver) == .granted)
	}

	@Test("-1743 is the ONE number that means the grant is missing")
	func notAuthorizedMeansNotGranted() {
		let runner = FakeAppleScriptRunner()
		runner.failNext(number: VoiceOverGestureSender.notAuthorized)
		#expect(TCCPermissionBroker(scripts: runner).status(of: .automationVoiceOver) == .notGranted)
	}

	@Test("the reader not running is NOT a permission answer")
	func readerNotRunningCannotTell() {
		// -600 is the reader being absent, and reporting it as `notGranted` would
		// send a human to System Settings to fix a grant they already hold. That
		// is the same class of wrong answer as the API this replaced, arrived at
		// from the other direction, so it is asserted rather than assumed.
		let runner = FakeAppleScriptRunner()
		runner.failNext(number: VoiceOverGestureSender.applicationIsNotRunning)
		#expect(TCCPermissionBroker(scripts: runner).status(of: .automationVoiceOver) == .cannotTell)
	}

	@Test("a wedged scripting object model is not a permission answer either")
	func wedgedObjectModelCannotTell() throws {
		// Spec 0041's -1728/-1708 pair: VoiceOver alive, its object model dead.
		// The recovery is a reader restart and has nothing to do with a grant.
		for number in VoiceOverGestureSender.objectModelDead {
			let runner = FakeAppleScriptRunner()
			runner.failNext(number: number)
			#expect(
				TCCPermissionBroker(scripts: runner).status(of: .automationVoiceOver) == .cannotTell,
				"error \(number) is not evidence about a permission"
			)
		}
	}

	@Test("a failure with no number at all cannot tell us anything")
	func unnumberedFailureCannotTell() {
		// `OSAScriptRunner` reports an unnumbered failure as number 0 rather than
		// classifying it -- a tool that died, an empty stderr. Guessing at one is
		// how a bridge tells an agent something confident and wrong.
		let runner = FakeAppleScriptRunner()
		runner.failNext(number: 0, message: "the script failed")
		#expect(TCCPermissionBroker(scripts: runner).status(of: .automationVoiceOver) == .cannotTell)
	}

	@Test("a tool that could not be launched cannot tell us anything")
	func processFailureCannotTell() {
		// Not an AppleScriptError at all: `osascript` itself failed to run. It
		// takes the same path, which is why the catch-all is a `catch` rather than
		// a second typed clause.
		struct NotAnAppleScriptError: Error {}
		let runner = FakeAppleScriptRunner()
		runner.answers = [.failure(NotAnAppleScriptError())]
		#expect(TCCPermissionBroker(scripts: runner).status(of: .automationVoiceOver) == .cannotTell)
	}

	@Test("reading a permission asks the human for nothing")
	func readingAsksNobody() {
		// The probe is a READ (`return name`), so neither a granted machine nor an
		// ungranted one raises a consent dialog. That is what keeps this safe to
		// call at startup on a machine nobody is sitting at, and it is asserted
		// here as a property of the SCRIPT because there is no other way to
		// observe "no dialog appeared" from a test.
		let runner = FakeAppleScriptRunner()
		runner.defaultAnswer = "VoiceOver"
		_ = TCCPermissionBroker(scripts: runner).status(of: .automationVoiceOver)
		let script = runner.scripts.joined()
		#expect(!script.contains("perform command"))
		#expect(!script.contains("set "))
	}
}
