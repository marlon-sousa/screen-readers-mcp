// Mirrors Sources/VoiceOverBridgeDomain/Entities/CommandVocabulary.swift.

import Testing

@testable import VoiceOverBridgeDomain

@Suite("CommandVocabulary")
struct CommandVocabularyTests {
	@Test("AN ENGLISH COMMAND NAME IS REFUSED, AND THE REFUSAL TEACHES THE ROUTE")
	func aCommandNameIsRefused() {
		for name in ["go to desktop", "describe item in voiceover cursor", "mute speech toggle"] {
			do {
				_ = try CommandVocabulary.classify(name, readerModifier: .controlOption)
				Issue.record("expected '\(name)' to be refused")
			} catch let refusal as GestureIdRefused {
				#expect(refusal.gesture == name)
				#expect(refusal.description.contains("command names"))
				#expect(refusal.description.contains("vo+m"))
				#expect(refusal.description.contains("Commands menu"))
				#expect(!refusal.description.contains("\(CommandVocabulary.keyboardSource):\(name)"))
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
	}

	@Test("a phrase containing a HYPHEN is refused as a phrase, not as VO-D notation")
	func hyphensInsideRealCommandsAreNotChords() {
		for name in [
			"toggle single-key quick nav on or off", "toggle arrow-key quick nav on or off",
		] {
			do {
				_ = try CommandVocabulary.classify(name, readerModifier: .controlOption)
				Issue.record("expected '\(name)' to be refused")
			} catch let refusal as GestureIdRefused {
				#expect(refusal.description.contains("Commands menu"))
				#expect(!refusal.description.contains("hyphen shorthand"))
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
	}

	@Test("A LONE TOKEN IS REFUSED, AND THE REFUSAL NAMES ITS PREFIXED FORM")
	func aLoneTokenIsRefused() {
		do {
			_ = try CommandVocabulary.classify("h", readerModifier: .controlOption)
			Issue.record("expected 'h' to be refused")
		} catch let refusal as GestureIdRefused {
			#expect(refusal.description.contains("kb:h"))
			#expect(refusal.description.contains("single key"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("A `+`-JOINED ID IS A KEYSTROKE, WHICH IS WHAT 13.17 CHANGED")
	func plusJoinedIdsAreKeystrokes() throws {
		#expect(
			try CommandVocabulary.classify("command+l", readerModifier: .controlOption)
				== Keystroke(modifiers: [.command], keys: [.character("l")]))
		#expect(
			try CommandVocabulary.classify("control+option+space", readerModifier: .controlOption)
				== Keystroke(
					modifiers: [.control, .option], keys: [.named(.space)],
					holdsReaderModifier: true))
	}

	@Test("TWO ORDINARY KEYS ARE A KEYSTROKE HERE TOO, and the vocabulary needed no change")
	func twoOrdinaryKeysClassifyAsAKeystroke() throws {
		#expect(
			try CommandVocabulary.classify("leftArrow+rightArrow", readerModifier: .controlOption)
				== Keystroke(modifiers: [], keys: [.named(.leftArrow), .named(.rightArrow)]))
		#expect(
			try CommandVocabulary.classify("kb:leftArrow+rightArrow", readerModifier: .controlOption)
				== CommandVocabulary.classify("leftArrow+rightArrow", readerModifier: .controlOption))
	}

	@Test("THE SPACE RULE IS WHAT DECIDES: `command key` is a phrase, `command+l` is a chord")
	func theSpaceRuleSeparatesThem() throws {
		#expect(throws: GestureIdRefused.self) {
			try CommandVocabulary.classify("command key", readerModifier: .controlOption)
		}
		#expect(
			try CommandVocabulary.classify("command+l", readerModifier: .controlOption).keys
				== [.character("l")])
	}

	@Test("`kb:h` IS THE LETTER KEY AND `h` IS A COMMAND NAME -- the whole of 13.19")
	func theSourcePrefixSaysWhichVocabulary() throws {
		#expect(
			try CommandVocabulary.classify("kb:h", readerModifier: .controlOption)
				== Keystroke(modifiers: [], keys: [.character("h")]))
		#expect(throws: GestureIdRefused.self) {
			try CommandVocabulary.classify("h", readerModifier: .controlOption)
		}
	}

	@Test("the prefix is accepted on a chord too, and changes nothing about it")
	func theSourcePrefixIsAcceptedOnAChord() throws {
		#expect(try CommandVocabulary.classify("kb:command+l", readerModifier: .controlOption) == CommandVocabulary.classify("command+l", readerModifier: .controlOption))
		#expect(
			CommandVocabulary.identifier(
				for: try CommandVocabulary.classify("KB:Down", readerModifier: .controlOption))
				== "kb:downArrow")
	}

	@Test("THE PREFIX OUTRANKS THE SHAPE OF WHAT FOLLOWS IT")
	func anExplicitPrefixIsNotSecondGuessed() {
		do {
			_ = try CommandVocabulary.classify("kb:go to desktop", readerModifier: .controlOption)
			Issue.record("expected 'kb:go to desktop' to be refused")
		} catch let refusal as GestureIdRefused {
			#expect(refusal.gesture == "kb:go to desktop")
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("a source this bridge does not know is refused BY NAME, naming the one it knows")
	func unknownSourcesAreRefusedByName() {
		for id in ["mouse:left", "touch:swipe"] {
			do {
				_ = try CommandVocabulary.classify(id, readerModifier: .controlOption)
				Issue.record("expected '\(id)' to be refused")
			} catch let refusal as GestureIdRefused {
				#expect(refusal.description.contains("kb:"))
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
	}

	@Test("NVDA's layout-qualified source is refused, and says why there is none here")
	func theQualifiedSourceIsRefused() {
		do {
			_ = try CommandVocabulary.classify("kb(laptop):h", readerModifier: .controlOption)
			Issue.record("expected 'kb(laptop):h' to be refused")
		} catch let refusal as GestureIdRefused {
			#expect(refusal.description.contains("read live"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("a COLON INSIDE A PHRASE is not a source -- the space rule again")
	func aColonAfterAPhraseIsNotASource() {
		do {
			_ = try CommandVocabulary.classify("say this: now", readerModifier: .controlOption)
			Issue.record("expected a refusal")
		} catch let refusal as GestureIdRefused {
			#expect(refusal.description.contains("Commands menu"))
			#expect(!refusal.description.contains("gesture source"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("a malformed keystroke is refused as a GESTURE ID, carrying the parse's reason")
	func malformedKeystrokesAreRefusedWithTheirReason() {
		do {
			_ = try CommandVocabulary.classify("cmd+l", readerModifier: .controlOption)
			Issue.record("expected 'cmd+l' to be refused")
		} catch let refusal as GestureIdRefused {
			#expect(refusal.gesture == "cmd+l")
			#expect(refusal.description.contains("is not a modifier"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("VoiceOver's own VO-D notation is STILL refused, and that is not an omission")
	func readerModifierNotationIsRefused() {
		for chord in ["VO-D", "Control-Option-Shift-Down", "Command-F5"] {
			do {
				_ = try CommandVocabulary.classify(chord, readerModifier: .controlOption)
				Issue.record("expected '\(chord)' to be refused")
			} catch let refusal as GestureIdRefused {
				#expect(refusal.gesture == chord)
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
	}

	@Test("THE REFUSAL NAMES THE REWRITE, which is 13.25's change to it")
	func theRefusalNamesTheRewrite() {
		do {
			_ = try CommandVocabulary.classify("VO-D", readerModifier: .controlOption)
			Issue.record("expected a refusal")
		} catch let refusal as GestureIdRefused {
			#expect(refusal.description.contains("vo+d"))
			#expect(!refusal.description.contains("control+option+d"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("the rewrite it names is the id the agent actually sent, lower-cased")
	func theRewriteQuotesTheIdSent() {
		do {
			_ = try CommandVocabulary.classify("VO-Shift-M", readerModifier: .controlOption)
			Issue.record("expected a refusal")
		} catch let refusal as GestureIdRefused {
			#expect(refusal.description.contains("vo+shift+m"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("an empty or whitespace-only id is refused, and says what an id looks like")
	func emptyIsRefused() {
		for empty in ["", "   ", "\n\t"] {
			do {
				_ = try CommandVocabulary.classify(empty, readerModifier: .controlOption)
				Issue.record("expected an empty id to be refused")
			} catch let refusal as GestureIdRefused {
				#expect(refusal.description.contains("empty"))
				#expect(refusal.description.contains("vo+m"))
				#expect(refusal.description.contains("command+l"))
				#expect(refusal.description.contains("kb:h"))
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
	}

	@Test("`identifier` is what the bridge UNDERSTOOD, not what it was handed")
	func describedReportsTheUnderstanding() throws {
		#expect(
			CommandVocabulary.identifier(
				for: try CommandVocabulary.classify("  Command+L\n", readerModifier: .controlOption))
				== "command+l")
	}

	@Test("THE SOURCE PREFIX APPEARS EXACTLY WHERE DROPPING IT WOULD LIE")
	func describedCarriesThePrefixOnlyWhenLoadBearing() throws {
		#expect(
			CommandVocabulary.identifier(
				for: try CommandVocabulary.classify("kb:h", readerModifier: .controlOption)) == "kb:h")
		#expect(
			CommandVocabulary.identifier(
				for: try CommandVocabulary.classify("kb:command+l", readerModifier: .controlOption))
				== "command+l")
		#expect(
			CommandVocabulary.identifier(
				for: try CommandVocabulary.classify("leftArrow+rightArrow", readerModifier: .controlOption))
				== "kb:leftArrow+rightArrow")
		for id in ["kb:h", "command+l", "kb:downArrow", "shift+command+4", "leftArrow+rightArrow"] {
			let spelled = CommandVocabulary.identifier(
				for: try CommandVocabulary.classify(id, readerModifier: .controlOption))
			#expect(
				CommandVocabulary.identifier(
					for: try CommandVocabulary.classify(spelled, readerModifier: .controlOption)) == spelled)
		}
	}

	@Test("`vo+m` IS A KEYSTROKE, classified by the `+` like every other one")
	func voIsAKeystroke() throws {
		#expect(
			try CommandVocabulary.classify("vo+m", readerModifier: .controlOption)
				== Keystroke(
					modifiers: [.control, .option], keys: [.character("m")],
					holdsReaderModifier: true))
	}

	@Test("the `kb:` prefix is accepted on one too, and changes nothing")
	func theSourcePrefixIsAcceptedOnAVoChord() throws {
		#expect(
			try CommandVocabulary.classify("kb:vo+m", readerModifier: .controlOption)
				== CommandVocabulary.classify("vo+m", readerModifier: .controlOption))
	}

	@Test("a PHRASE containing those two letters is not read as a modifier")
	func aCommandNameIsNotAModifier() {
		do {
			_ = try CommandVocabulary.classify(
				"toggle the vo modifier lock on or off", readerModifier: .controlOption)
			Issue.record("expected a refusal")
		} catch let refusal as GestureIdRefused {
			#expect(refusal.description.contains("Commands menu"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("A REFUSED `vo` IS REPORTED AGAINST THE ID THE AGENT SENT")
	func theRefusalQuotesTheIdSent() {
		do {
			_ = try CommandVocabulary.classify("kb:vo+m", readerModifier: .capsLock)
			Issue.record("expected a refusal on a Caps Lock machine")
		} catch let refusal as GestureIdRefused {
			#expect(refusal.gesture == "kb:vo+m")
			#expect(refusal.description.contains("CAPS LOCK"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}
}
