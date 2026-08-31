// Mirrors Sources/VoiceOverBridgeDomain/Entities/CommandVocabulary.swift.
//
// The property under test is a ROUTING DECISION, not a format: this reader takes
// its own English command names AND keystrokes, they go to two different places
// at two different permission costs, and the id itself is all there is to tell
// them apart. The real command names asserted below were read out of the
// machine's own `SCRStringsToCommandsMap.scrconfig` -- 415 entries on macOS 15.0
// -- so the space rule is tested against the vocabulary it has to survive rather
// than against invented examples.
//
// THE NAMED TEST THAT REFUSED `control+l` WAS DELETED WITH 13.17, in the commit
// that made the promise keepable -- the pattern 13.6 and 13.10 both followed
// before it. What replaced it is the classification below: the same id, no
// longer refused, and now asserted to take the SYSTEM route rather than the
// reader one. The refusal that survives is `VO-D`, and it survives for a reason
// no feature can retire (see below).

import Testing

@testable import VoiceOverBridgeDomain

@Suite("CommandVocabulary")
struct CommandVocabularyTests {
	// -- the reader's own commands ---------------------------------------------

	@Test("an English command name passes through untouched, as a READER command")
	func aCommandNamePasses() throws {
		#expect(try CommandVocabulary.classify("go to desktop") == .readerCommand("go to desktop"))
		#expect(
			try CommandVocabulary.classify("describe item in voiceover cursor")
				== .readerCommand("describe item in voiceover cursor"))
	}

	@Test("a real command name containing a HYPHEN passes -- the vocabulary has three")
	func hyphensInsideRealCommandsPass() throws {
		// This is the case that makes the naive "a hyphen means a chord" rule
		// wrong, and both of these are real entries in the machine's own map.
		#expect(
			try CommandVocabulary.classify("toggle single-key quick nav on or off")
				== .readerCommand("toggle single-key quick nav on or off"))
		#expect(
			try CommandVocabulary.classify("toggle arrow-key quick nav on or off")
				== .readerCommand("toggle arrow-key quick nav on or off"))
	}

	@Test("a command that presses a key THROUGH the reader is still a command")
	func keyCommandsPass() throws {
		// "f8 key" and "command key" are in the vocabulary, and they cost no
		// Accessibility grant -- so they stay the cheap route to a single key, and
		// refusing them would be this entity mistaking a command name for the thing
		// it is named after. The modifiers among them famously DO NOT COMPOSE
		// (`scripts/voiceover_modifiers.sh`), which is why a chord needs the other
		// route rather than two of these.
		#expect(try CommandVocabulary.classify("f8 key") == .readerCommand("f8 key"))
		#expect(try CommandVocabulary.classify("command key") == .readerCommand("command key"))
	}

	@Test("surrounding whitespace is trimmed, and nothing else is touched")
	func whitespaceIsTrimmed() throws {
		// The one liberty taken with an opaque value: a trailing space would fail
		// as `Command does not exist` and no agent would ever see why. Internal
		// spacing and case are the reader's business.
		#expect(try CommandVocabulary.classify("  go to desktop\n") == .readerCommand("go to desktop"))
		#expect(try CommandVocabulary.classify("Go To Desktop") == .readerCommand("Go To Desktop"))
	}

	// -- keystrokes ------------------------------------------------------------

	@Test("A `+`-JOINED ID IS A KEYSTROKE, WHICH IS WHAT 13.17 CHANGED")
	func plusJoinedIdsAreKeystrokes() throws {
		// Until this entry each of these was refused outright, and the bridge had
		// no way at all to send Command-L -- which is how everybody actually uses a
		// Mac. The agent that has driven the other reader in this contract sends
		// exactly this notation, and now it works.
		#expect(
			try CommandVocabulary.classify("command+l")
				== .keystroke(Keystroke(modifiers: [.command], key: .character("l"))))
		#expect(
			try CommandVocabulary.classify("control+option+space")
				== .keystroke(Keystroke(modifiers: [.control, .option], key: .named(.space))))
	}

	@Test("THE SPACE RULE IS WHAT DECIDES: `command key` is a command, `command+l` is not")
	func theSpaceRuleSeparatesThem() throws {
		// The whole discriminator, in one assertion. Every real command name that
		// carries a separator carries spaces too, and no command in the 415 is a
		// bare `+`-joined token -- so the rule that decides is one this file
		// already lived by before there was anything to decide between.
		#expect(try CommandVocabulary.classify("command key").isKeystroke == false)
		#expect(try CommandVocabulary.classify("command+l").isKeystroke == true)
	}

	@Test("a malformed keystroke is refused as a GESTURE ID, carrying the parse's reason")
	func malformedKeystrokesAreRefusedWithTheirReason() {
		// The classification is right and the contents are wrong, so the agent must
		// hear the second thing rather than being told to send a command name.
		do {
			_ = try CommandVocabulary.classify("cmd+l")
			Issue.record("expected 'cmd+l' to be refused")
		} catch let refusal as GestureIdRefused {
			#expect(refusal.gesture == "cmd+l")
			#expect(refusal.description.contains("is not a modifier"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	// -- what is still refused, and why no feature retires it -------------------

	@Test("VoiceOver's own VO-D notation is STILL refused, and that is not an omission")
	func readerModifierNotationIsRefused() {
		// It is neither a command the reader will dispatch nor a keystroke this
		// bridge can construct: "VO" is whatever the user bound their VoiceOver
		// modifier to -- Control-Option, or Caps Lock, or both -- so pressing it
		// would mean guessing at somebody's own configuration and pressing the
		// wrong keys with total confidence. That is the exact mistake this type was
		// written to catch, and 13.17 does not change it.
		for chord in ["VO-D", "Control-Option-Shift-Down", "Command-F5"] {
			do {
				_ = try CommandVocabulary.classify(chord)
				Issue.record("expected '\(chord)' to be refused")
			} catch let refusal as GestureIdRefused {
				#expect(refusal.gesture == chord)
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
	}

	@Test("the refusal says what to send instead, in both currencies")
	func theRefusalNamesBothAlternatives() {
		// A refusal that did not carry the alternative would be a complaint rather
		// than a recovery -- and here there are two, because the agent may have
		// meant either: the reader's command name, or those literal keys.
		do {
			_ = try CommandVocabulary.classify("VO-D")
			Issue.record("expected a refusal")
		} catch let refusal as GestureIdRefused {
			#expect(refusal.description.contains("describe item in voiceover cursor"))
			#expect(refusal.description.contains("control+option+d"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("an empty or whitespace-only id is refused, and says what an id looks like")
	func emptyIsRefused() {
		for empty in ["", "   ", "\n\t"] {
			do {
				_ = try CommandVocabulary.classify(empty)
				Issue.record("expected an empty id to be refused")
			} catch let refusal as GestureIdRefused {
				#expect(refusal.description.contains("empty"))
				// Both routes named, because both are available now.
				#expect(refusal.description.contains("go to desktop"))
				#expect(refusal.description.contains("command+l"))
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
	}

	// -- what the handler reports ----------------------------------------------

	@Test("`described` is what the bridge UNDERSTOOD, not what it was handed")
	func describedReportsTheUnderstanding() throws {
		// It is what goes in the transcript and in the `pressed` entry, so a reader
		// of either sees which keys went out rather than an echo of the agent's own
		// text.
		#expect(try CommandVocabulary.classify("  go to desktop ").described == "go to desktop")
		#expect(try CommandVocabulary.classify("Command+L").described == "command+l")
	}
}
