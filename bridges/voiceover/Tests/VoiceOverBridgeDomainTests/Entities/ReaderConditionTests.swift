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

	@Test("the lost-voice recovery puts RE-REGISTRATION before the restart")
	func reRegistrationComesFirst() {
		let recovery = ReaderCondition.captureVoiceNotOfferedByReader.recovery
		guard let register = recovery.range(of: "pluginkit -a"),
			let restart = recovery.range(of: "restart VoiceOver")
		else {
			Issue.record("the recovery no longer names both steps")
			return
		}
		#expect(register.lowerBound < restart.lowerBound)
		// And it says the restart alone is not enough, which is the half that was
		// measured and would otherwise be re-derived by whoever tries it.
		#expect(recovery.contains("NOT to be enough"))
	}

	@Test("registration names lsregister BEFORE pluginkit, because the first alone was not enough")
	func lsregisterComesFirst() {
		// Spec 0041, C1: `lsregister -f` on the app then `pluginkit -a` on the
		// .appex; the first on its own did not register the voice.
		let recovery = ReaderCondition.providerNotRunning.recovery
		guard let lsregister = recovery.range(of: "lsregister -f"),
			let pluginkit = recovery.range(of: "pluginkit -a")
		else {
			Issue.record("the recovery no longer names both tools")
			return
		}
		#expect(lsregister.lowerBound < pluginkit.lowerBound)
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
		#expect(ReaderCondition.scriptingChannelDead.recovery.contains("restart VoiceOver"))
	}
}
