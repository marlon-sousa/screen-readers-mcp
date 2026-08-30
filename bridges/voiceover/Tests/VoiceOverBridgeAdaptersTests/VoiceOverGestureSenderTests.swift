// Mirrors Sources/VoiceOverBridgeAdapters/VoiceOverGestureSender.swift.
//
// THIS FILE IS WHY THE APPLESCRIPT SEAM EXISTS. Every assertion below is a
// finding that cost a live measurement on the maintainer's own screen reader --
// which object a command is addressed to, and what each error number means --
// and none of them will ever need one again.
//
// The first suite is the one that matters most. Spec 0047 recorded
// `perform command` as DEAD on this host, failing with error 4 for every name
// including a bogus one, and board entry 13.7 carried that as a measured risk it
// could not be planned around. It was not dead: the command was addressed to the
// wrong OBJECT. `VoiceOver.sdef` says the `application` class does not respond
// to `perform command` and the `commander object` does, and sending a command to
// an object that does not handle it fails before any name lookup -- which is
// exactly why a good name and a bad one failed identically.

import Fakes
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("VoiceOverGestureSender")
struct VoiceOverGestureSenderTests {
	private func sender(_ runner: FakeAppleScriptRunner) -> VoiceOverGestureSender {
		VoiceOverGestureSender(runner: runner)
	}

	// -- the target ------------------------------------------------------------

	@Test("the command is addressed to the COMMANDER, which is the whole finding")
	func theCommandGoesToTheCommander() throws {
		let runner = FakeAppleScriptRunner()
		try sender(runner).press("go to desktop")
		let script = try #require(runner.scripts.first)
		#expect(script.contains("tell commander to perform command"))
		#expect(script.contains("\"go to desktop\""))
	}

	@Test("it is NOT addressed to the application, which fails identically for every name")
	func theCommandDoesNotGoToTheApplication() throws {
		// Asserted as a negative on purpose. A "simplification" back to
		// `tell application "VoiceOver" to perform command` compiles, reads
		// better, and restores a state in which every gesture fails with error 4
		// and no message tells you why. That is what happened between spec 0041
		// and spec 0047.
		let runner = FakeAppleScriptRunner()
		try sender(runner).press("go to desktop")
		let script = try #require(runner.scripts.first)
		#expect(!script.contains("VoiceOver\" to perform command"))
	}

	@Test("a quote in a command name cannot end the script's string literal")
	func commandNamesAreEscaped() throws {
		// A gesture id is opaque text off the wire, placed inside a quoted literal
		// in a script that drives somebody's screen reader.
		let runner = FakeAppleScriptRunner()
		try sender(runner).press("say \"hello\" now")
		let script = try #require(runner.scripts.first)
		#expect(script.contains("\\\"hello\\\""))
		#expect(script.hasSuffix("\""))
	}

	@Test("a backslash is escaped before the quotes it would otherwise escape")
	func backslashesAreEscapedFirst() throws {
		let runner = FakeAppleScriptRunner()
		try sender(runner).press("back\\slash")
		#expect(try #require(runner.scripts.first).contains("back\\\\slash"))
	}

	// -- the error codes -------------------------------------------------------

	@Test("6 is an unknown command -- the clean failure this route was chosen for")
	func sixIsAnUnknownCommand() throws {
		let runner = FakeAppleScriptRunner()
		runner.failNext(number: 6, message: "Command does not exist.")
		#expect(throws: GestureError.unknownCommand("no such command at all")) {
			try sender(runner).press("no such command at all")
		}
	}

	@Test("-1728 and -1708 are both the scripting object model dying")
	func theObjectModelDeaths() throws {
		// Spec 0041 measured both while VoiceOver itself kept running and kept
		// answering its own name. They mean one thing to a caller and both need a
		// reader restart, so they collapse into one case here and nowhere earlier.
		for number in [-1728, -1708] {
			let runner = FakeAppleScriptRunner()
			runner.failNext(number: number)
			#expect(throws: GestureError.scriptingChannelDead) {
				try sender(runner).press("go to desktop")
			}
		}
	}

	@Test("error 4 is reported WITH the measurement that explains it")
	func fourCarriesItsExplanation() throws {
		// The one error whose obvious reading is wrong. If this bridge ever sees
		// it from a commander-addressed command, the reader's object model is not
		// the one this adapter was written against -- and whoever reads the
		// message should be told that rather than left to rediscover it.
		let runner = FakeAppleScriptRunner()
		runner.failNext(number: 4, message: "Erro de AppleEvent.")
		do {
			try sender(runner).press("go to desktop")
			Issue.record("expected the dispatch to fail")
		} catch let error as GestureError {
			#expect(error.description.contains("APPLICATION"))
			#expect(error.description.contains("2026-08-30"))
		}
	}

	@Test("-1743 names the Automation grant, which is the failure a first run hits")
	func notAuthorizedNamesTheGrant() throws {
		let runner = FakeAppleScriptRunner()
		runner.failNext(number: -1743, message: "Not authorized to send Apple events to VoiceOver.")
		do {
			try sender(runner).press("go to desktop")
			Issue.record("expected the dispatch to fail")
		} catch let error as GestureError {
			#expect(error.description.contains("Automation"))
			// Both halves: the system grant, and VoiceOver's own enablement flag.
			// They are different switches and a run can be missing either.
			#expect(error.description.contains("VoiceOver Utility"))
		}
	}

	@Test("-600 says the reader is not running, and how to start it")
	func notRunningSaysHowToStart() throws {
		let runner = FakeAppleScriptRunner()
		runner.failNext(number: -600, message: "Application isn't running.")
		do {
			try sender(runner).press("go to desktop")
			Issue.record("expected the dispatch to fail")
		} catch let error as GestureError {
			#expect(error.description.contains("Command-F5"))
		}
	}

	@Test("an unrecognised number is reported as ITSELF, never classified into a guess")
	func anUnknownNumberIsReportedVerbatim() throws {
		let runner = FakeAppleScriptRunner()
		runner.failNext(number: -2700, message: "algo deu errado")
		do {
			try sender(runner).press("go to desktop")
			Issue.record("expected the dispatch to fail")
		} catch let error as GestureError {
			#expect(error.description.contains("-2700"))
			#expect(error.description.contains("algo deu errado"))
			#expect(error.description.contains("go to desktop"))
		}
	}

	@Test("a tool that could not be run at all is not blamed on the reader")
	func aToolFailureIsNotAReaderFailure() throws {
		let runner = FakeAppleScriptRunner()
		runner.answers = [.failure(ProcessFailure("could not run /usr/bin/osascript"))]
		do {
			try sender(runner).press("go to desktop")
			Issue.record("expected the dispatch to fail")
		} catch let error as GestureError {
			guard case .failed(let detail) = error else {
				Issue.record("expected a plain failure, got \(error)")
				return
			}
			#expect(detail.contains("could not run the script"))
		}
	}
}
