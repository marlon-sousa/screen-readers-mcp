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
		#expect(try CommandVocabulary.classify("go to desktop", readerModifier: .controlOption) == .readerCommand("go to desktop"))
		#expect(
			try CommandVocabulary.classify("describe item in voiceover cursor", readerModifier: .controlOption)
				== .readerCommand("describe item in voiceover cursor"))
	}

	@Test("a real command name containing a HYPHEN passes -- the vocabulary has three")
	func hyphensInsideRealCommandsPass() throws {
		// This is the case that makes the naive "a hyphen means a chord" rule
		// wrong, and both of these are real entries in the machine's own map.
		#expect(
			try CommandVocabulary.classify("toggle single-key quick nav on or off", readerModifier: .controlOption)
				== .readerCommand("toggle single-key quick nav on or off"))
		#expect(
			try CommandVocabulary.classify("toggle arrow-key quick nav on or off", readerModifier: .controlOption)
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
		#expect(try CommandVocabulary.classify("f8 key", readerModifier: .controlOption) == .readerCommand("f8 key"))
		#expect(try CommandVocabulary.classify("command key", readerModifier: .controlOption) == .readerCommand("command key"))
	}

	@Test("surrounding whitespace is trimmed, and nothing else is touched")
	func whitespaceIsTrimmed() throws {
		// The one liberty taken with an opaque value: a trailing space would fail
		// as `Command does not exist` and no agent would ever see why. Internal
		// spacing and case are the reader's business.
		#expect(try CommandVocabulary.classify("  go to desktop\n", readerModifier: .controlOption) == .readerCommand("go to desktop"))
		#expect(try CommandVocabulary.classify("Go To Desktop", readerModifier: .controlOption) == .readerCommand("Go To Desktop"))
	}

	// -- keystrokes ------------------------------------------------------------

	@Test("A `+`-JOINED ID IS A KEYSTROKE, WHICH IS WHAT 13.17 CHANGED")
	func plusJoinedIdsAreKeystrokes() throws {
		// Until this entry each of these was refused outright, and the bridge had
		// no way at all to send Command-L -- which is how everybody actually uses a
		// Mac. The agent that has driven the other reader in this contract sends
		// exactly this notation, and now it works.
		#expect(
			try CommandVocabulary.classify("command+l", readerModifier: .controlOption)
				== .keystroke(Keystroke(modifiers: [.command], keys: [.character("l")])))
		#expect(
			try CommandVocabulary.classify("control+option+space", readerModifier: .controlOption)
				== .keystroke(Keystroke(modifiers: [.control, .option], keys: [.named(.space)])))
	}

	@Test("TWO ORDINARY KEYS ARE A KEYSTROKE HERE TOO, and the vocabulary needed no change")
	func twoOrdinaryKeysClassifyAsAKeystroke() throws {
		// 13.22 at this layer, and the claim worth recording is that this file did
		// not change: `+` with no space is a keystroke whatever the tokens are, so
		// the entity below was the only thing that had to learn a second key. The
		// chord is arrow-key Quick Nav, which is the one an agent meets first.
		#expect(
			try CommandVocabulary.classify("leftArrow+rightArrow", readerModifier: .controlOption)
				== .keystroke(Keystroke(modifiers: [], keys: [.named(.leftArrow), .named(.rightArrow)])))
		#expect(
			try CommandVocabulary.classify("kb:leftArrow+rightArrow", readerModifier: .controlOption)
				== CommandVocabulary.classify("leftArrow+rightArrow", readerModifier: .controlOption))
		// And it costs the Accessibility grant exactly as a one-key chord does --
		// a `CGEvent` is a `CGEvent` -- which is what keeps 13.8's lever intact.
		#expect(try CommandVocabulary.classify("leftArrow+rightArrow", readerModifier: .controlOption).isKeystroke == true)
	}

	@Test("THE SPACE RULE IS WHAT DECIDES: `command key` is a command, `command+l` is not")
	func theSpaceRuleSeparatesThem() throws {
		// The whole discriminator, in one assertion. Every real command name that
		// carries a separator carries spaces too, and no command in the 415 is a
		// bare `+`-joined token -- so the rule that decides is one this file
		// already lived by before there was anything to decide between.
		#expect(try CommandVocabulary.classify("command key", readerModifier: .controlOption).isKeystroke == false)
		#expect(try CommandVocabulary.classify("command+l", readerModifier: .controlOption).isKeystroke == true)
	}

	// -- the source prefix, which is 13.19 --------------------------------------

	@Test("`kb:h` IS THE LETTER KEY AND `h` IS A COMMAND NAME -- the whole of 13.19")
	func theSourcePrefixSaysWhichVocabulary() throws {
		// With single-key Quick Nav on, an ordinary VoiceOver user presses `h` to
		// move by heading, and until this entry there was no way to ask for it: the
		// `+` was the whole discriminator, so a bare `h` was looked up as one of the
		// reader's commands and refused. The prefix is NVDA's own -- lane 1 strips
		// exactly this shape -- and spec 0018 reserved the namespace for the first
		// reader where an unprefixed id does not mean the keyboard. This one.
		#expect(
			try CommandVocabulary.classify("kb:h", readerModifier: .controlOption)
				== .keystroke(Keystroke(modifiers: [], keys: [.character("h")])))
		#expect(try CommandVocabulary.classify("h", readerModifier: .controlOption) == .readerCommand("h"))
	}

	@Test("the prefix is accepted on a chord too, and changes nothing about it")
	func theSourcePrefixIsAcceptedOnAChord() throws {
		// An agent that has learned the prefix should not have to learn where NOT
		// to write it, and lane 1 accepts it on everything.
		#expect(try CommandVocabulary.classify("kb:command+l", readerModifier: .controlOption) == CommandVocabulary.classify("command+l", readerModifier: .controlOption))
		#expect(try CommandVocabulary.classify("KB:Down", readerModifier: .controlOption).described == "kb:downArrow")
	}

	@Test("THE PREFIX OUTRANKS THE SHAPE OF WHAT FOLLOWS IT")
	func anExplicitPrefixIsNotSecondGuessed() {
		// `kb:go to desktop` is a malformed keystroke and not a command name. The
		// agent said which vocabulary it meant; the answer to a mistake is to name
		// it rather than to route around it.
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
		// `kb(laptop):` picks one of NVDA's own gesture maps. Here the layout that
		// matters is the machine's own, read live when the key is pressed -- so
		// there is nothing for a qualifier to select, and saying so is more use
		// than "unknown source".
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
	func aColonAfterAPhraseIsNotASource() throws {
		// Checked on the machine rather than assumed: none of the 415 entries in
		// `SCRStringsToCommandsMap.scrconfig` contains a colon. If one ever does,
		// this is the rule that keeps it a command name.
		#expect(
			try CommandVocabulary.classify("say this: now", readerModifier: .controlOption) == .readerCommand("say this: now"))
	}

	@Test("a malformed keystroke is refused as a GESTURE ID, carrying the parse's reason")
	func malformedKeystrokesAreRefusedWithTheirReason() {
		// The classification is right and the contents are wrong, so the agent must
		// hear the second thing rather than being told to send a command name.
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
		// The refusal survives and its REASON does not. It used to say that `VO` is
		// whatever the person bound it to and this bridge would not guess, and it
		// sent the agent to a command name or to `control+option+d`. Both of those
		// answers are now wrong in a small way: `vo` IS a modifier here, resolved
		// from the machine, so `VO-D` is one separator away from an id that works
		// -- and `control+option+d` is only correct on a machine whose modifier is
		// Control-Option, which this bridge now knows and the agent does not.
		do {
			_ = try CommandVocabulary.classify("VO-D", readerModifier: .controlOption)
			Issue.record("expected a refusal")
		} catch let refusal as GestureIdRefused {
			#expect(refusal.description.contains("vo+d"))
			#expect(refusal.description.contains("describe item in voiceover cursor"))
			// Not sent to the literal keys any more: on a Caps Lock machine they are
			// not the modifier, and this refusal cannot see which machine it is on.
			#expect(!refusal.description.contains("control+option+d"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("the rewrite it names is the id the agent actually sent, lower-cased")
	func theRewriteQuotesTheIdSent() {
		// A generic "write it with +" would leave an agent that sent `VO-Shift-M`
		// composing the answer itself, which is exactly where a wrong modifier
		// order gets invented.
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
		#expect(try CommandVocabulary.classify("  go to desktop ", readerModifier: .controlOption).described == "go to desktop")
		#expect(try CommandVocabulary.classify("Command+L", readerModifier: .controlOption).described == "command+l")
	}

	@Test("THE SOURCE PREFIX APPEARS EXACTLY WHERE DROPPING IT WOULD LIE")
	func describedCarriesThePrefixOnlyWhenLoadBearing() throws {
		// A transcript line has to be replayable, and `h` fed back in is a command
		// name -- so a modifier-free keystroke keeps its prefix. A chord does not
		// need one, and going without keeps the spelling identical to lane 1's
		// documented form, which is the point of standardizing on it.
		#expect(try CommandVocabulary.classify("kb:h", readerModifier: .controlOption).described == "kb:h")
		#expect(try CommandVocabulary.classify("kb:command+l", readerModifier: .controlOption).described == "command+l")
		// A multi-key chord with no modifiers keeps the prefix too -- 13.22. It
		// would round-trip without one, since the `+` classifies it; the rule stays
		// "no modifiers, so say which vocabulary" rather than growing a clause.
		#expect(
			try CommandVocabulary.classify("leftArrow+rightArrow", readerModifier: .controlOption).described
				== "kb:leftArrow+rightArrow")
		for id in ["kb:h", "command+l", "kb:downArrow", "shift+command+4", "leftArrow+rightArrow"] {
			let described = try CommandVocabulary.classify(id, readerModifier: .controlOption).described
			#expect(try CommandVocabulary.classify(described, readerModifier: .controlOption).described == described)
		}
	}

	// -- `vo` at the vocabulary, which is 13.25 ---------------------------------

	@Test("`vo+m` IS A KEYSTROKE, classified by the `+` like every other one")
	func voIsAKeystroke() throws {
		// No new notation and no new source: it contains a `+` and no space, so the
		// rules that were already here classify it.
		#expect(
			try CommandVocabulary.classify("vo+m", readerModifier: .controlOption)
				== .keystroke(Keystroke(modifiers: [.control, .option], keys: [.character("m")])))
	}

	@Test("the `kb:` prefix is accepted on one too, and changes nothing")
	func theSourcePrefixIsAcceptedOnAVoChord() throws {
		#expect(
			try CommandVocabulary.classify("kb:vo+m", readerModifier: .controlOption)
				== CommandVocabulary.classify("vo+m", readerModifier: .controlOption))
	}

	@Test("a COMMAND NAME containing those two letters is untouched")
	func aCommandNameIsNotAModifier() throws {
		// The space rule does this work, and it is worth an assertion because `vo`
		// is now a token with a meaning: "toggle the vo modifier lock on or off" is
		// one of the reader's 415 commands and must still reach the reader.
		#expect(
			try CommandVocabulary.classify("toggle the vo modifier lock on or off",
				readerModifier: .controlOption)
				== .readerCommand("toggle the vo modifier lock on or off"))
	}

	@Test("A REFUSED `vo` IS REPORTED AGAINST THE ID THE AGENT SENT")
	func theRefusalQuotesTheIdSent() {
		// The re-quoting rule this file already lives by: a `kb:vo+m` that fails
		// must say `kb:vo+m` and not `vo+m`, or the agent is left looking for an id
		// it never wrote.
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
