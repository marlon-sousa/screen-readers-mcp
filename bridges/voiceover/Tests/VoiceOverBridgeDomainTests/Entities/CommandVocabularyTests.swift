// Mirrors Sources/VoiceOverBridgeDomain/Entities/CommandVocabulary.swift.
//
// The property under test is a BOUNDARY, not a format: this reader's gesture
// channel takes English command names, and a keystroke sent as a gesture is the
// one mistake the reader itself cannot diagnose usefully. The real command names
// asserted below were read out of the machine's own
// `SCRStringsToCommandsMap.scrconfig` -- 415 entries on macOS 15.0 -- so the
// hyphen rule is tested against the vocabulary it has to survive rather than
// against invented examples.

import Testing

@testable import VoiceOverBridgeDomain

@Suite("CommandVocabulary")
struct CommandVocabularyTests {
	@Test("an English command name passes through untouched")
	func aCommandNamePasses() throws {
		#expect(try CommandVocabulary.accept("go to desktop") == "go to desktop")
		#expect(
			try CommandVocabulary.accept("describe item in voiceover cursor")
				== "describe item in voiceover cursor")
	}

	@Test("a real command name containing a HYPHEN passes -- the vocabulary has three")
	func hyphensInsideRealCommandsPass() throws {
		// This is the case that makes the naive "a hyphen means a chord" rule
		// wrong, and all three are real entries in the machine's own map.
		#expect(
			try CommandVocabulary.accept("toggle single-key quick nav on or off")
				== "toggle single-key quick nav on or off")
		#expect(
			try CommandVocabulary.accept("toggle arrow-key quick nav on or off")
				== "toggle arrow-key quick nav on or off")
	}

	@Test("a command that presses a key THROUGH the reader is a command, not a keystroke")
	func keyCommandsPass() throws {
		// "f8 key" and "command key" are in the vocabulary. They are the honest
		// route to a keypress before 13.8 exists, and refusing them would be this
		// entity mistaking a command name for the thing it is named after.
		#expect(try CommandVocabulary.accept("f8 key") == "f8 key")
		#expect(try CommandVocabulary.accept("command key") == "command key")
	}

	@Test("surrounding whitespace is trimmed, and nothing else is touched")
	func whitespaceIsTrimmed() throws {
		// The one liberty taken with an opaque value: a trailing space would fail
		// as `Command does not exist` and no agent would ever see why. Internal
		// spacing and case are the reader's business.
		#expect(try CommandVocabulary.accept("  go to desktop\n") == "go to desktop")
		#expect(try CommandVocabulary.accept("Go To Desktop") == "Go To Desktop")
	}

	@Test("an NVDA-style key combo is refused BY NAME, with what to send instead")
	func plusJoinedCombosAreRefused() {
		// The agent that has driven the other reader in this contract sends these.
		for combo in ["NVDA+f7", "control+l", "insert+down"] {
			do {
				_ = try CommandVocabulary.accept(combo)
				Issue.record("expected '\(combo)' to be refused")
			} catch let refusal as GestureIdRefused {
				#expect(refusal.gesture == combo)
				#expect(refusal.description.contains("key combination"))
				// The message has to carry the alternative, or it is a complaint
				// rather than a recovery.
				#expect(refusal.description.contains("go to desktop"))
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
	}

	@Test("a VoiceOver-documentation chord is refused too, and that is the harder half")
	func hyphenChordsAreRefused() {
		// VoiceOver's own documentation writes shortcuts this way, so this is the
		// form an agent reading Apple's docs will send. A single token with a
		// hyphen and no spaces.
		for chord in ["VO-D", "Control-Option-Shift-Down", "Command-F5"] {
			do {
				_ = try CommandVocabulary.accept(chord)
				Issue.record("expected '\(chord)' to be refused")
			} catch let refusal as GestureIdRefused {
				#expect(refusal.gesture == chord)
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
	}

	@Test("the refusal explains WHY this reader has no keystrokes, not just that it refused")
	func theRefusalNamesTheMechanism() {
		// The agent's mistake is not a typo -- it is that this channel dispatches
		// commands rather than keys, which is also why no Accessibility grant is
		// asked for. A refusal that did not say so would train an agent to keep
		// guessing at spellings.
		do {
			_ = try CommandVocabulary.accept("VO-D")
			Issue.record("expected a refusal")
		} catch let refusal as GestureIdRefused {
			#expect(refusal.description.contains("COMMAND NAMES"))
			#expect(refusal.description.contains("Accessibility"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("an empty or whitespace-only id is refused, and says what an id looks like")
	func emptyIsRefused() {
		for empty in ["", "   ", "\n\t"] {
			do {
				_ = try CommandVocabulary.accept(empty)
				Issue.record("expected an empty id to be refused")
			} catch let refusal as GestureIdRefused {
				#expect(refusal.description.contains("empty"))
				#expect(refusal.description.contains("go to desktop"))
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
	}
}
