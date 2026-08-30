// Mirrors Sources/VoiceOverBridgeAdapters/VoiceOverLiveness.swift.
//
// The property under test is that the probe stays the NARROWEST question that
// separates "the object model died" from "the reader is gone". `return name` is
// an application-level property, which is exactly why spec 0041 could measure it
// still answering while every VoiceOver-specific call failed. A richer probe
// would fail alongside the call it is meant to be a control for.

import Fakes
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("VoiceOverLiveness")
struct VoiceOverLivenessTests {
	@Test("it asks for the reader's own name and nothing else")
	func itAsksForTheName() throws {
		let runner = FakeAppleScriptRunner()
		runner.defaultAnswer = "VoiceOver"
		_ = VoiceOverLiveness(runner: runner).readerAnswersItsOwnName()
		let script = try #require(runner.scripts.first)
		#expect(script == "tell application \"VoiceOver\" to return name")
		// Nothing that needs the object model: no cursor, no last phrase, no
		// window. Those are the calls this one is the control FOR.
		#expect(!script.contains("cursor"))
		#expect(!script.contains("last phrase"))
	}

	@Test("an answer in ANY language counts, because the name is localized")
	func anyNonEmptyAnswerCounts() {
		// The lane's no-reader-strings rule: the maintainer's machine speaks
		// Portuguese. That it answered at all is the signal; comparing the text
		// with "VoiceOver" would be a test that passes in English only.
		let runner = FakeAppleScriptRunner()
		runner.defaultAnswer = "Voz Over"
		#expect(VoiceOverLiveness(runner: runner).readerAnswersItsOwnName())
	}

	@Test("an empty answer is not an answer")
	func emptyIsNotAnAnswer() {
		let runner = FakeAppleScriptRunner()
		runner.defaultAnswer = ""
		#expect(!VoiceOverLiveness(runner: runner).readerAnswersItsOwnName())
	}

	@Test("every failure is a `no`, and none of them escapes")
	func everyFailureIsANo() {
		// The port promises not to throw: its one caller is already handling a
		// failure, and every way this can fail is a "no" as far as that caller is
		// concerned. What each failure MEANS is the gesture sender's business and
		// it has already said so by the time this is asked.
		for failure in [
			AppleScriptError(number: -600, message: "not running") as any Error,
			AppleScriptError(number: -1743, message: "not authorized"),
			ProcessFailure("could not run /usr/bin/osascript"),
		] {
			let runner = FakeAppleScriptRunner()
			runner.answers = [.failure(failure)]
			#expect(!VoiceOverLiveness(runner: runner).readerAnswersItsOwnName())
		}
	}
}
