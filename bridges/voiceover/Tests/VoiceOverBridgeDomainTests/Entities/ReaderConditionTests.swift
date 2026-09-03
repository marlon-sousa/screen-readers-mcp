// Mirrors Sources/VoiceOverBridgeDomain/Entities/ReaderCondition.swift.
//
// THE RECOVERIES ARE THE TEST. Each was measured rather than reasoned about, and
// the one that matters most is counter-intuitive: restarting the reader is
// NECESSARY AND NOT SUFFICIENT for a voice that vanished from VoiceOver's list
// (spec 0047, finding 6). A file that lost that ordering would send a person to
// restart their screen reader repeatedly, which is exactly what happened before
// it was written down -- five times in one afternoon.
//
// No test compares reader strings, per the lane's rule; these are OUR strings,
// written here, and asserted for the facts they must carry rather than word for
// word.

import Testing

@testable import VoiceOverBridgeDomain

@Suite("ReaderCondition")
struct ReaderConditionTests {
	@Test("every condition carries a summary and a recovery, and neither is empty")
	func allAreActionable() {
		for condition in ReaderCondition.allCases {
			#expect(!condition.summary.isEmpty)
			#expect(!condition.recovery.isEmpty)
		}
	}

	@Test("the lost-voice recovery leaves the human ONE step, because the bridge does the other")
	func theBridgeHasAlreadyReRegistered() {
		// UNTIL 13.20 THIS ASSERTED AN ORDER -- re-register, THEN restart -- because
		// both halves were the human's. The handshake registers the extension
		// itself now, so the recovery that reaches an agent has to say so: a
		// sentence telling somebody to re-register something the bridge just
		// re-registered is a sentence that wastes their afternoon differently.
		let recovery = ReaderCondition.captureVoiceNotOfferedByReader.recovery
		#expect(recovery.contains(readerRestartCommand))
		#expect(recovery.contains("already done the re-registration"))
		// And it still says the restart alone is not enough, which is the measured
		// half and would otherwise be re-derived by whoever tries it.
		#expect(recovery.contains("NOT to be enough"))
	}

	@Test("registration names lsregister BEFORE pluginkit, because the first alone was not enough")
	func lsregisterComesFirst() {
		// Spec 0041, C1: `lsregister -f` on the app then `pluginkit -a` on the
		// .appex; the first on its own did not register the voice. The order is
		// still stated even though the bridge now performs it, because this is what
		// a human runs by hand when the bridge could not find its own bundle.
		let recovery = ReaderCondition.providerNotRunning.recovery
		guard let lsregister = recovery.range(of: "lsregister -f"),
			let pluginkit = recovery.range(of: "pluginkit -a")
		else {
			Issue.record("the recovery no longer names both tools")
			return
		}
		#expect(lsregister.lowerBound < pluginkit.lowerBound)
	}

	@Test("NO RESTART SENTENCE MAY NAME THE KILL WITHOUT THE WAIT AND THE OPEN")
	func aRestartIsNeverJustAKillall() {
		// MEASURED 2026-08-31: `killall VoiceOver` does NOT relaunch the reader.
		// A recovery that stopped after the kill is one somebody could follow into
		// silence, so no sentence in this file may name the kill on its own.
		for condition in ReaderCondition.allCases where condition.recovery.contains("killall") {
			#expect(condition.recovery.contains(readerRestartCommand))
		}
		// AND THE PAIR ITSELF WAS WRONG UNTIL 13.26. `killall && open -a` races:
		// killall returns when the signal is sent, so `open` fires into a reader the
		// system still believes is running and does nothing at all. The 2026-09-02
		// field report followed this repository's own advice into exactly that, and
		// asked for "either restart the reader the way that works, or print the
		// gesture that works". The gesture is Command-F5.
		#expect(readerRestartCommand.contains("Command-F5"))
		#expect(!readerRestartCommand.contains("killall VoiceOver && open"))
		// The shell form is still offered, and it is spelled with its WAIT.
		#expect(readerRestartCommand.contains("WAIT"))
		#expect(readerRestartCommand.contains("open -a VoiceOver"))
	}

	@Test("a reader that is not running is its OWN condition, separate from a dead object model")
	func theReaderNotRunningIsNamed() {
		// 13.20 needs the distinction: `scriptingChannelDead` is the reader
		// answering its name and nothing else, and this is the reader not answering
		// at all. Different diagnoses, different recoveries -- which is the whole
		// argument for this file being an enum rather than a string in a handler.
		#expect(ReaderCondition.readerNotRunning != ReaderCondition.scriptingChannelDead)
		#expect(ReaderCondition.readerNotRunning.recovery.contains("open -a VoiceOver"))
		// It does NOT tell a human to restart: the bridge starts the reader itself,
		// and a restart takes it away from somebody who may be using it.
		#expect(!ReaderCondition.readerNotRunning.recovery.contains("killall"))
	}

	@Test("the described form carries the name, the summary and the recovery together")
	func describedCarriesEverything() {
		let described = ReaderCondition.captureVoiceNotSelected.described
		#expect(described.contains("captureVoiceNotSelected"))
		#expect(described.contains(ReaderCondition.captureVoiceNotSelected.summary))
		#expect(described.contains(ReaderCondition.captureVoiceNotSelected.recovery))
	}

	@Test("the scripting-channel condition exists, and 13.7 is what detects it")
	func theScriptingConditionIsNamed() {
		// Written down before anything reports it, deliberately: this file is the
		// vocabulary, and a condition that lives in a spec and in no type is one
		// that gets rediscovered as an empty read-back.
		#expect(ReaderCondition.scriptingChannelDead.recovery.contains(readerRestartCommand))
	}
}
