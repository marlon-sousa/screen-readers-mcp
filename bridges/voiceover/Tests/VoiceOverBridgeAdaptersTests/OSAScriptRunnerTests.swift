// Mirrors Sources/VoiceOverBridgeAdapters/OSAScriptRunner.swift.
//
// THIS FILE IS THE LAYOUT AMENDMENT, ARGUED. Spec 0046 names `OSAScriptRunner` a
// leaf adapter -- untestable by construction, and therefore with no test file at
// all. Running `osascript` through the ProcessRunner seam that 13.6 already
// built moves the one decision it makes above the line, and this is that
// decision under test: recovering the error NUMBER from what the tool wrote.
//
// The stderr shapes below were measured on 2026-08-30 with scripts that touch no
// screen reader at all (`osascript -e 'error "boom" number 6'`, `-e '1/0'`), so
// the format is real rather than remembered. The Portuguese in them is not
// decoration: it is the machine's own language, and it is the reason nothing
// here may branch on a message.

import Fakes
import Foundation
import Testing

@testable import VoiceOverBridgeAdapters

@Suite("OSAScriptRunner")
struct OSAScriptRunnerTests {
	private func runner(_ process: FakeProcessRunner) -> OSAScriptRunner {
		OSAScriptRunner(runner: process)
	}

	private func succeeding(_ output: String) -> FakeProcessRunner {
		let process = FakeProcessRunner()
		process.answers["-e"] = ProcessResult(status: 0, standardOutput: Data(output.utf8))
		return process
	}

	private func failing(_ stderr: String) -> FakeProcessRunner {
		let process = FakeProcessRunner()
		process.answers["-e"] = ProcessResult(
			status: 1, standardOutput: Data(), standardError: stderr)
		return process
	}

	// -- running ---------------------------------------------------------------

	@Test("it runs the system osascript, by absolute path")
	func itRunsTheSystemTool() throws {
		let process = succeeding("")
		_ = try runner(process).run("tell application \"VoiceOver\" to return name")
		let call = try #require(process.invocations.first)
		// An absolute path rather than a PATH lookup: a PATH entry must not get to
		// decide what drives somebody's screen reader.
		#expect(call.executable == "/usr/bin/osascript")
		#expect(call.arguments == ["-e", "tell application \"VoiceOver\" to return name"])
	}

	@Test("the answer comes back without the newline osascript adds")
	func theAnswerIsTrimmed() throws {
		#expect(try runner(succeeding("VoiceOver\n")).run("anything") == "VoiceOver")
	}

	// -- the number ------------------------------------------------------------

	@Test("the trailing number is recovered, and it is all that may be reasoned about")
	func theNumberIsRecovered() throws {
		let failure = OSAScriptRunner.failure(from: "6:12: execution error: boom (6)\n")
		#expect(failure.number == 6)
		#expect(failure.message == "boom")
	}

	@Test("a LOCALIZED message survives with its number, which is the whole point")
	func aLocalizedMessageKeepsItsNumber() {
		// Measured verbatim on the maintainer's machine. A caller that matched on
		// message text would pass every test written in English and fail here.
		let failure = OSAScriptRunner.failure(
			from: "2:3: execution error: Não é possível dividir 1.0 por zero. (-2701)\n")
		#expect(failure.number == -2701)
		#expect(failure.message == "Não é possível dividir 1.0 por zero.")
	}

	@Test("osascript's own LINE:COL preamble is dropped -- it is about our script")
	func thePreambleIsDropped() {
		let failure = OSAScriptRunner.failure(from: "21:30: execution error: whatever (-2753)")
		#expect(!failure.message.contains("execution error"))
		#expect(!failure.message.contains("21:30"))
	}

	@Test("the LAST parenthesised number wins, because the message may contain its own")
	func theLastNumberWins() {
		let failure = OSAScriptRunner.failure(
			from: "execution error: VoiceOver (the reader) got an error (-1728)")
		#expect(failure.number == -1728)
	}

	@Test("only the LAST line is read, so a multi-line stderr does not confuse it")
	func onlyTheLastLineIsRead() {
		let failure = OSAScriptRunner.failure(from: "some warning\n0:0: execution error: no (6)\n")
		#expect(failure.number == 6)
	}

	@Test("a failure with no number is reported verbatim, never classified into a guess")
	func anUnnumberedFailureIsNotGuessedAt() {
		// Every caller above this line switches on the number. `0` is the value
		// that matches none of their cases, which is what makes such a failure
		// come out as itself instead of as somebody's best guess.
		let failure = OSAScriptRunner.failure(from: "the tool died\n")
		#expect(failure.number == 0)
		#expect(failure.message == "the tool died")
		#expect(failure.description == "the tool died")
	}

	@Test("an empty stderr still produces a readable failure")
	func anEmptyStderrIsStillReadable() {
		let failure = OSAScriptRunner.failure(from: "")
		#expect(failure.number == 0)
		#expect(!failure.message.isEmpty)
	}

	@Test("parentheses that are not a number do not become one")
	func nonNumericParenthesesAreNotANumber() {
		let failure = OSAScriptRunner.failure(from: "execution error: something (unknown)")
		#expect(failure.number == 0)
	}

	// -- through the seam ------------------------------------------------------

	@Test("a non-zero exit throws an AppleScriptError carrying the number")
	func aFailedRunThrows() {
		let process = failing("6:12: execution error: Command does not exist. (6)")
		#expect(throws: AppleScriptError(number: 6, message: "Command does not exist.")) {
			try runner(process).run("tell application \"VoiceOver\" to return name")
		}
	}

	@Test("a tool that cannot be launched throws the process failure, not a script error")
	func aMissingToolIsADifferentFailure() {
		// Different things, and the callers treat them differently: one is the
		// reader refusing, the other is this machine being unable to ask.
		let process = FakeProcessRunner()
		process.failure = ProcessFailure("could not run /usr/bin/osascript")
		#expect(throws: ProcessFailure.self) {
			try runner(process).run("anything")
		}
	}
}
