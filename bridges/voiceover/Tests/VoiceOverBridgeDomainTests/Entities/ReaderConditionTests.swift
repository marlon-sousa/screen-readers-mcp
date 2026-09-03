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

	@Test("a reader that is not running is its own named condition")
	func theReaderNotRunningIsNamed() {
		// IT WAS HALF OF A PAIR UNTIL 13.31: `scriptingChannelDead` was the reader
		// answering its name and nothing else, and this was the reader not answering
		// at all -- different diagnoses, different recoveries, which was the whole
		// argument for this file being an enum. The other half went with the
		// AppleScript channel it described, and this one is now the only question
		// worth asking about the reader's existence.
		#expect(ReaderCondition.readerNotRunning.recovery.contains("open -a VoiceOver"))
		// It does NOT tell a human to restart: the bridge starts the reader itself,
		// and a restart takes it away from somebody who may be using it.
		#expect(!ReaderCondition.readerNotRunning.recovery.contains("killall"))
	}

	@Test("THE USER'S OWN VOICE NAMES THE SETTINGS PATH IN FULL, because it is read ALOUD")
	func theUsersVoiceRecoveryIsSpeakable() {
		// 13.24. This is the one recovery in the file the bridge SPEAKS -- Marlon,
		// 2026-09-03: *"that handshake announcement must let the user know and give
		// them instructions to install the voice."* A half-named path is a path
		// somebody hunts for, and they cannot see the screen while they hunt.
		let recovery = ReaderCondition.usersVoiceNotAvailable.recovery
		#expect(recovery.contains("System Settings"))
		#expect(recovery.contains("Spoken Content"))
		#expect(recovery.contains("Manage Voices"))
		// AND IT PROMISES NOTHING IT CANNOT BACK UP. The list this condition is
		// derived from publishes voices that are advertised and not installed
		// (13.15), so "install it" is the action and "the reader will sound right
		// again" is not a claim this bridge may make.
		#expect(!recovery.contains("will sound"))
		// It also says the session is carrying on, because it is: this condition is
		// not a refusal, and a sentence that read like one would send somebody to fix
		// something before reconnecting when nothing is waiting on them.
		#expect(recovery.contains("running normally"))
	}

	@Test("it is the one condition NO ProviderState reports, and that is on purpose")
	func theUsersVoiceIsNotAProviderState() {
		// Every other case describes where OUR capture voice has got to, so
		// `ProviderState` owns which are live. This one is about the PERSON'S voice,
		// which no state of ours has an opinion about -- it is read directly by
		// `ReaderEdgeSetup` and `Session`. A future entry that folds it into a state
		// mapping would make a handshake report the user's voice as a fault of the
		// capture pipeline.
		for state in ProviderState.allCases {
			#expect(!state.conditions.contains(.usersVoiceNotAvailable))
			#expect(!state.unheardConditions.contains(.usersVoiceNotAvailable))
		}
	}

	@Test("the described form carries the name, the summary and the recovery together")
	func describedCarriesEverything() {
		let described = ReaderCondition.captureVoiceNotSelected.described
		#expect(described.contains("captureVoiceNotSelected"))
		#expect(described.contains(ReaderCondition.captureVoiceNotSelected.summary))
		#expect(described.contains(ReaderCondition.captureVoiceNotSelected.recovery))
	}
}
