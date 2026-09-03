// Mirrors Sources/VoiceOverBridgeDomain/Entities/CommandVocabulary.swift.
//
// THE PROPERTY UNDER TEST STOPPED BEING A ROUTING DECISION AT 13.31. It was one
// for eight entries: this reader took its own English command names AND
// keystrokes, they went to two different places at two different permission
// costs, and the id was all there was to tell them apart. There is one
// destination now -- no VoiceOver user can type a command name, so neither does a
// session standing in for one (spec 0055) -- and what is left here is a
// vocabulary: which ids are keystrokes, and what every other id is told.
//
// SO HALF THE TESTS IN THIS FILE ARE REFUSALS THAT USED TO BE ACCEPTANCES, and
// they are kept in that shape on purpose rather than deleted. The phrases below
// were read out of the machine's own `SCRStringsToCommandsMap.scrconfig` -- 415
// entries on macOS 15.0 -- and every agent that has driven this bridge, and every
// document written about it before now, says to send exactly them. What the
// refusal has to do is teach the route a person takes, and that is asserted here
// rather than assumed.
//
// THE NAMED TEST THAT REFUSED `control+l` WAS DELETED WITH 13.17, in the commit
// that made the promise keepable -- the pattern 13.6 and 13.10 both followed
// before it, and the pattern this entry follows in the other direction. The
// refusal that survives untouched is `VO-D`, for a reason no feature retires.

import Testing

@testable import VoiceOverBridgeDomain

@Suite("CommandVocabulary")
struct CommandVocabularyTests {
	// -- what is no longer a gesture id -----------------------------------------

	@Test("AN ENGLISH COMMAND NAME IS REFUSED, AND THE REFUSAL TEACHES THE ROUTE")
	func aCommandNameIsRefused() {
		// The whole of 13.31 at this layer. These are real entries in the reader's
		// own vocabulary and they were accepted here until this entry, so an agent
		// carrying any earlier guidance will send one. The refusal must not read as
		// "unknown gesture": the act is reachable, by the key it is bound to or
		// through the menu a person uses when there is no key.
		for name in ["go to desktop", "describe item in voiceover cursor", "mute speech toggle"] {
			do {
				_ = try CommandVocabulary.classify(name, readerModifier: .controlOption)
				Issue.record("expected '\(name)' to be refused")
			} catch let refusal as GestureIdRefused {
				#expect(refusal.gesture == name)
				#expect(refusal.description.contains("command names"))
				// The key, and the menu for an act that has none.
				#expect(refusal.description.contains("vo+m"))
				#expect(refusal.description.contains("Commands menu"))
				// AND NOT THE `kb:` CLAUSE, which is the fix 13.31's own live run
				// bought: sending `go to menu bar` came back advising
				// `kb:go to menu bar`, a malformed keystroke the next call would also
				// refuse. A refusal that names an unusable id costs a round trip and
				// teaches a spelling that does not exist.
				#expect(!refusal.description.contains("\(CommandVocabulary.keyboardSource):\(name)"))
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
	}

	@Test("a phrase containing a HYPHEN is refused as a phrase, not as VO-D notation")
	func hyphensInsideRealCommandsAreNotChords() {
		// This is the case that makes the naive "a hyphen means a chord" rule
		// wrong, and both of these are real entries in the machine's own map. The
		// space rule still decides, and it decides between two REFUSALS now -- so
		// the assertion is which message the agent gets, and it is the useful one.
		for name in [
			"toggle single-key quick nav on or off", "toggle arrow-key quick nav on or off",
		] {
			do {
				_ = try CommandVocabulary.classify(name, readerModifier: .controlOption)
				Issue.record("expected '\(name)' to be refused")
			} catch let refusal as GestureIdRefused {
				#expect(refusal.description.contains("Commands menu"))
				// NOT the hyphen-shorthand message, which would tell an agent to
				// rewrite a sentence with plus signs in it.
				#expect(!refusal.description.contains("hyphen shorthand"))
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
	}

	@Test("A LONE TOKEN IS REFUSED, AND THE REFUSAL NAMES ITS PREFIXED FORM")
	func aLoneTokenIsRefused() {
		// `f8 key` and `command key` were commands that pressed a key THROUGH the
		// reader, and a bare `return` was one too -- which is why an unprefixed lone
		// token was never a keystroke here. That reasoning is gone with the route,
		// and the rule is kept anyway: `kb:h` is what the transcript writes and what
		// lane 1 writes, so a notation that accepted `h` as well would be one an
		// agent has to learn twice. The refusal costs one round trip and names the
		// spelling that works.
		do {
			_ = try CommandVocabulary.classify("h", readerModifier: .controlOption)
			Issue.record("expected 'h' to be refused")
		} catch let refusal as GestureIdRefused {
			// A LONE TOKEN GETS THE CLAUSE A PHRASE DOES NOT, which is the whole of
			// the distinction: `kb:h` is a keystroke and `kb:go to menu bar` is not.
			#expect(refusal.description.contains("kb:h"))
			#expect(refusal.description.contains("single key"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
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
				== Keystroke(modifiers: [.command], keys: [.character("l")]))
		#expect(
			try CommandVocabulary.classify("control+option+space", readerModifier: .controlOption)
				== Keystroke(
					modifiers: [.control, .option], keys: [.named(.space)],
					holdsReaderModifier: true))
	}

	@Test("TWO ORDINARY KEYS ARE A KEYSTROKE HERE TOO, and the vocabulary needed no change")
	func twoOrdinaryKeysClassifyAsAKeystroke() throws {
		// 13.22 at this layer, and the claim worth recording is that this file did
		// not change: `+` with no space is a keystroke whatever the tokens are, so
		// the entity below was the only thing that had to learn a second key. The
		// chord is arrow-key Quick Nav, which is the one an agent meets first.
		#expect(
			try CommandVocabulary.classify("leftArrow+rightArrow", readerModifier: .controlOption)
				== Keystroke(modifiers: [], keys: [.named(.leftArrow), .named(.rightArrow)]))
		#expect(
			try CommandVocabulary.classify("kb:leftArrow+rightArrow", readerModifier: .controlOption)
				== CommandVocabulary.classify("leftArrow+rightArrow", readerModifier: .controlOption))
	}

	@Test("THE SPACE RULE IS WHAT DECIDES: `command key` is a phrase, `command+l` is a chord")
	func theSpaceRuleSeparatesThem() throws {
		// The discriminator, in one test. It used to separate two acceptances --
		// `command key` was one of the reader's own commands -- and it now separates
		// an acceptance from a refusal, which is a smaller job for the same rule.
		#expect(throws: GestureIdRefused.self) {
			try CommandVocabulary.classify("command key", readerModifier: .controlOption)
		}
		#expect(
			try CommandVocabulary.classify("command+l", readerModifier: .controlOption).keys
				== [.character("l")])
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
				== Keystroke(modifiers: [], keys: [.character("h")]))
		// `h` bare was a COMMAND NAME until 13.31 and is now a refusal that names
		// this spelling -- see `aLoneTokenIsRefused`. The prefix still does the
		// deciding; what it decides between has changed.
		#expect(throws: GestureIdRefused.self) {
			try CommandVocabulary.classify("h", readerModifier: .controlOption)
		}
	}

	@Test("the prefix is accepted on a chord too, and changes nothing about it")
	func theSourcePrefixIsAcceptedOnAChord() throws {
		// An agent that has learned the prefix should not have to learn where NOT
		// to write it, and lane 1 accepts it on everything.
		#expect(try CommandVocabulary.classify("kb:command+l", readerModifier: .controlOption) == CommandVocabulary.classify("command+l", readerModifier: .controlOption))
		#expect(
			CommandVocabulary.identifier(
				for: try CommandVocabulary.classify("KB:Down", readerModifier: .controlOption))
				== "kb:downArrow")
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
	func aColonAfterAPhraseIsNotASource() {
		// A source is a single token, so a phrase before the colon means the colon
		// is part of the phrase -- which is refused as a phrase, with the route a
		// person takes, rather than as an unknown source. The distinction matters
		// because the two messages send an agent to different places.
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
				// The notation, spelled the three ways an id can look.
				#expect(refusal.description.contains("vo+m"))
				#expect(refusal.description.contains("command+l"))
				#expect(refusal.description.contains("kb:h"))
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
	}

	// -- what the handler reports ----------------------------------------------

	@Test("`identifier` is what the bridge UNDERSTOOD, not what it was handed")
	func describedReportsTheUnderstanding() throws {
		// It is what goes in the transcript and in the `pressed` entry, so a reader
		// of either sees which keys went out rather than an echo of the agent's own
		// text. Surrounding whitespace is trimmed on the way in, which is the one
		// liberty taken with an opaque id.
		#expect(
			CommandVocabulary.identifier(
				for: try CommandVocabulary.classify("  Command+L\n", readerModifier: .controlOption))
				== "command+l")
	}

	@Test("THE SOURCE PREFIX APPEARS EXACTLY WHERE DROPPING IT WOULD LIE")
	func describedCarriesThePrefixOnlyWhenLoadBearing() throws {
		// A transcript line has to be replayable, and `h` fed back in is a command
		// name -- so a modifier-free keystroke keeps its prefix. A chord does not
		// need one, and going without keeps the spelling identical to lane 1's
		// documented form, which is the point of standardizing on it.
		#expect(
			CommandVocabulary.identifier(
				for: try CommandVocabulary.classify("kb:h", readerModifier: .controlOption)) == "kb:h")
		#expect(
			CommandVocabulary.identifier(
				for: try CommandVocabulary.classify("kb:command+l", readerModifier: .controlOption))
				== "command+l")
		// A multi-key chord with no modifiers keeps the prefix too -- 13.22. It
		// would round-trip without one, since the `+` classifies it; the rule stays
		// "no modifiers, so say which vocabulary" rather than growing a clause.
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

	// -- `vo` at the vocabulary, which is 13.25 ---------------------------------

	@Test("`vo+m` IS A KEYSTROKE, classified by the `+` like every other one")
	func voIsAKeystroke() throws {
		// No new notation and no new source: it contains a `+` and no space, so the
		// rules that were already here classify it.
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
		// The space rule does this work, and it is worth an assertion because `vo`
		// is a token with a meaning: "toggle the vo modifier lock on or off" is one
		// of the reader's own acts, and an agent will send it here. What it must get
		// back is the phrase refusal with the route, not a complaint about a chord.
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
