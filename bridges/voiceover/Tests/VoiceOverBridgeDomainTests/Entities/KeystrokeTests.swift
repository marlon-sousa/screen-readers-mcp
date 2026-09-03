// Mirrors Sources/VoiceOverBridgeDomain/Entities/Keystroke.swift.
//
// The property under test is that AN ID AN AGENT WROTE MEANS EXACTLY ONE
// KEYSTROKE, or fails saying why. Everything below this entity is a system event
// nobody can watch: a chord that pressed the wrong key would look identical to a
// chord the application ignored, so every mistake that CAN be caught before an
// event is posted is caught here, by name.

import Testing

@testable import VoiceOverBridgeDomain

@Suite("Keystroke")
struct KeystrokeTests {
	// -- parsing ---------------------------------------------------------------

	@Test("the plainest chord there is")
	func commandL() throws {
		// The one this whole board entry exists for: opening a location in Safari.
		let keystroke = try Keystroke.parse("command+l", readerModifier: .controlOption)
		#expect(keystroke.modifiers == [.command])
		#expect(keystroke.keys == [.character("l")])
	}

	@Test("several modifiers, in any order among themselves")
	func modifierOrderDoesNotMatter() throws {
		// A set, not a list -- so the agent does not have to know a convention this
		// bridge never published.
		let written = try Keystroke.parse("shift+command+4", readerModifier: .controlOption)
		let reversed = try Keystroke.parse("command+shift+4", readerModifier: .controlOption)
		#expect(written == reversed)
		#expect(written.modifiers == [.command, .shift])
		#expect(written.keys == [.character("4")])
	}

	@Test("all five modifiers are known, including fn")
	func everyModifier() throws {
		let keystroke = try Keystroke.parse("fn+control+option+shift+command+t", readerModifier: .controlOption)
		#expect(keystroke.modifiers == [.fn, .control, .option, .shift, .command])
		#expect(keystroke.keys == [.character("t")])
	}

	@Test("case is not significant")
	func caseIsIgnored() throws {
		// An agent that has read Apple's documentation writes `Command+L`, and it
		// means the same key as `command+l` -- an uppercase letter here is a
		// spelling of the key, not a request for Shift.
		#expect(try Keystroke.parse("Command+L", readerModifier: .controlOption) == Keystroke.parse("command+l", readerModifier: .controlOption))
		#expect(try Keystroke.parse("CONTROL+Option+Space", readerModifier: .controlOption) == Keystroke.parse("control+option+space", readerModifier: .controlOption))
	}

	@Test("surrounding whitespace is trimmed, like a command name's")
	func whitespaceIsTrimmed() throws {
		#expect(try Keystroke.parse("  command+l\n", readerModifier: .controlOption) == Keystroke.parse("command+l", readerModifier: .controlOption))
	}

	// -- named keys ------------------------------------------------------------

	@Test("the named keys are keys, not characters -- they skip the layout entirely")
	func namedKeys() throws {
		// The distinction the adapter depends on: Return is in the same place on
		// every keyboard sold, and `l` is not.
		#expect(try Keystroke.parse("command+enter", readerModifier: .controlOption).keys == [.named(.enter)])
		#expect(try Keystroke.parse("control+escape", readerModifier: .controlOption).keys == [.named(.escape)])
		#expect(try Keystroke.parse("option+forwarddelete", readerModifier: .controlOption).keys == [.named(.forwardDelete)])
		#expect(try Keystroke.parse("command+leftarrow", readerModifier: .controlOption).keys == [.named(.leftArrow)])
		#expect(try Keystroke.parse("command+pagedown", readerModifier: .controlOption).keys == [.named(.pageDown)])
		#expect(try Keystroke.parse("command+space", readerModifier: .controlOption).keys == [.named(.space)])
	}

	// -- a key with no modifiers, which is 13.19 --------------------------------

	@Test("A LONE KEY IS A KEYSTROKE HERE, and that is what `kb:h` means")
	func aLoneKeyParses() throws {
		// The entry's whole point: with single-key Quick Nav on, an ordinary
		// VoiceOver user presses `h` to move by heading. The vocabulary decides
		// that a BARE `h` is one of the reader's command names and that `kb:h` is
		// this -- so by the time an id reaches here, a single token is a key.
		let quickNav = try Keystroke.parse("h", readerModifier: .controlOption)
		#expect(quickNav.modifiers.isEmpty)
		#expect(quickNav.keys == [.character("h")])
		#expect(try Keystroke.parse("enter", readerModifier: .controlOption) == Keystroke(modifiers: [], keys: [.named(.enter)]))
		#expect(try Keystroke.parse("F5", readerModifier: .controlOption) == Keystroke(modifiers: [], keys: [.named(.function(5))]))
	}

	// -- two ordinary keys held together, which is 13.22 ------------------------

	@Test("TWO ORDINARY KEYS HELD TOGETHER, which is how Quick Nav is toggled")
	func twoKeysTogether() throws {
		// The entry's whole point. Until it, this id failed with "'leftarrow' is
		// not a modifier this bridge knows" -- true, unhelpful, and pointing at the
		// wrong thing, while the chord it refused is how an ordinary VoiceOver user
		// turns on the navigation mode they then use all day.
		let quickNav = try Keystroke.parse("leftarrow+rightarrow", readerModifier: .controlOption)
		#expect(quickNav.modifiers.isEmpty)
		#expect(quickNav.keys == [.named(.leftArrow), .named(.rightArrow)])
	}

	@Test("THE ORDER OF THE KEYS IS KEPT, because it is what down-and-up-in-reverse means")
	func theOrderOfTheKeysIsKept() throws {
		// The modifiers are a set and the keys are a list, and this is the
		// difference: the adapter presses these in this order and releases them in
		// reverse, so a keystroke that reordered them would be a transcript line
		// nobody could replay.
		#expect(try Keystroke.parse("rightarrow+leftarrow", readerModifier: .controlOption).keys == [.named(.rightArrow), .named(.leftArrow)])
		#expect(try Keystroke.parse("leftarrow+rightarrow", readerModifier: .controlOption) != Keystroke.parse("rightarrow+leftarrow", readerModifier: .controlOption))
	}

	@Test("modifiers still come first, and they hold across ALL the keys")
	func modifiersHoldAcrossEveryKey() throws {
		// The reason for one notation rather than a second separator: a chord that
		// is both -- modifiers held over two ordinary keys -- has to be spellable,
		// and `+` already means "these together".
		let keystroke = try Keystroke.parse("command+leftarrow+rightarrow", readerModifier: .controlOption)
		#expect(keystroke.modifiers == [.command])
		#expect(keystroke.keys == [.named(.leftArrow), .named(.rightArrow)])
	}

	@Test("three keys are no different from two -- there is no cap")
	func threeKeys() throws {
		// An arbitrary limit of two would be a number nobody could defend, and the
		// code is identical for three. What bounds it is that every token has to be
		// a key this bridge names.
		#expect(try Keystroke.parse("a+b+c", readerModifier: .controlOption).keys == [.character("a"), .character("b"), .character("c")])
	}

	@Test("a multi-key chord round-trips through `described`, keys in order")
	func aMultiKeyChordRoundTrips() throws {
		#expect(try Keystroke.parse("leftArrow+rightArrow", readerModifier: .controlOption).described == "leftArrow+rightArrow")
		#expect(
			try Keystroke.parse("command+left+right", readerModifier: .controlOption).described == "command+leftArrow+rightArrow")
		for id in ["leftArrow+rightArrow", "command+left+right", "shift+a+b"] {
			let keystroke = try Keystroke.parse(id, readerModifier: .controlOption)
			#expect(try Keystroke.parse(keystroke.described, readerModifier: .controlOption) == keystroke)
		}
	}

	@Test("A MODIFIER AFTER A KEY IS STILL A NAMED FAILURE, and now says both fixes")
	func aModifierAfterAKeyIsRefused() {
		// The rule 13.22 had to be careful not to lose: the first token that is not
		// a modifier begins the keys, so `command` here is a modifier in the key
		// position rather than a key. It is refused rather than hoisted, because
		// the one place not to hide a typo is the one that presses a key.
		do {
			_ = try Keystroke.parse("leftarrow+command+rightarrow", readerModifier: .controlOption)
			Issue.record("expected a modifier after a key to be refused")
		} catch let malformed as KeystrokeMalformed {
			#expect(malformed.reason.contains("is a modifier"))
			#expect(malformed.reason.contains("leftArrow+rightArrow"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("a key in a multi-key chord that names nothing is refused, and nothing is guessed")
	func anUnknownKeyInAChordIsRefused() {
		// The message for a non-last token is the modifier one, because that is
		// overwhelmingly the mistake -- `cmd+l`. It still names the alternative, so
		// an agent writing a chord is not left thinking two keys are impossible.
		do {
			_ = try Keystroke.parse("leftarow+rightarrow", readerModifier: .controlOption)
			Issue.record("expected 'leftarow+rightarrow' to be refused")
		} catch let malformed as KeystrokeMalformed {
			#expect(malformed.reason.contains("leftArrow+rightArrow"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("f1 through f20, and nothing above f20")
	func functionKeys() throws {
		#expect(try Keystroke.parse("command+f1", readerModifier: .controlOption).keys == [.named(.function(1))])
		#expect(try Keystroke.parse("control+f20", readerModifier: .controlOption).keys == [.named(.function(20))])
		// f21 is not a key macOS names, so it is a character token of three
		// characters -- which is a named failure rather than a silent f2.
		#expect(throws: KeystrokeMalformed.self) { try Keystroke.parse("command+f21", readerModifier: .controlOption) }
		#expect(throws: KeystrokeMalformed.self) { try Keystroke.parse("command+f0", readerModifier: .controlOption) }
	}

	@Test("the MAC's spellings are accepted as synonyms for NVDA's names")
	func alternativeSpellings() throws {
		// Each of these is what somebody reading Apple's documentation -- or this
		// bridge's own guidance before 13.19 -- actually types, and each names the
		// same physical key as the canonical spelling beside it. Accepting them
		// costs a line each and saves a round trip that would fail for no good
		// reason. What is NOT accepted is a name that means a DIFFERENT key on the
		// other reader; those are refused below.
		#expect(try Keystroke.parse("command+return", readerModifier: .controlOption).keys == [.named(.enter)])
		#expect(try Keystroke.parse("command+esc", readerModifier: .controlOption).keys == [.named(.escape)])
		#expect(try Keystroke.parse("command+left", readerModifier: .controlOption).keys == [.named(.leftArrow)])
		#expect(try Keystroke.parse("command+down", readerModifier: .controlOption).keys == [.named(.downArrow)])
		#expect(try Keystroke.parse("command+up", readerModifier: .controlOption).keys == [.named(.upArrow)])
		#expect(try Keystroke.parse("command+right", readerModifier: .controlOption).keys == [.named(.rightArrow)])
		// `alt` is `option`: one physical key, two labels, and Apple prints both.
		#expect(try Keystroke.parse("alt+t", readerModifier: .controlOption) == Keystroke.parse("option+t", readerModifier: .controlOption))
	}

	@Test("EVERY TOKEN ACCEPTED HERE NAMES THE SAME KEY ON NVDA -- spec 0049 §2.3")
	func nvdaNamesAreTheCanonicalOnes() throws {
		// Read out of `../nvda/source/vkCodes.py` at release-2026.1 rather than
		// recalled. Three of these previously spelled themselves in a way that
		// FAILS on lane 1 -- `fromName` looks its tokens up in `vkCodes.byName`,
		// which has `enter`, `leftArrow` and `pageUp` and has never had `return`,
		// `left` or `pageup` -- so a transcript line from this reader could not be
		// replayed on the other one.
		#expect(try Keystroke.parse("command+return", readerModifier: .controlOption).described == "command+enter")
		#expect(try Keystroke.parse("command+left", readerModifier: .controlOption).described == "command+leftArrow")
		#expect(try Keystroke.parse("command+down", readerModifier: .controlOption).described == "command+downArrow")
		#expect(try Keystroke.parse("command+pageup", readerModifier: .controlOption).described == "command+pageUp")
		#expect(try Keystroke.parse("command+backspace", readerModifier: .controlOption).described == "command+backspace")
		#expect(try Keystroke.parse("alt+t", readerModifier: .controlOption).described == "option+t")
	}

	// -- what fails, and by name -----------------------------------------------

	@Test("a missing key is refused, and says what the notation looks like")
	func missingKey() {
		for id in ["command+", "+l", "command++l"] {
			do {
				_ = try Keystroke.parse(id, readerModifier: .controlOption)
				Issue.record("expected '\(id)' to be refused")
			} catch let malformed as KeystrokeMalformed {
				#expect(malformed.id == id)
				#expect(malformed.reason.contains("empty"))
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
	}

	@Test("A NAME THAT MEANS A DIFFERENT KEY ON THE OTHER READER IS REFUSED, NOT MAPPED")
	func ambiguousKeyNamesAreRefused() {
		// `delete` is the one that made this rule worth having: on this machine it
		// erases BACKWARDS and on Windows it erases FORWARDS, so accepting it would
		// mean one gesture id doing two different things on the contract's two
		// readers with nothing anywhere to see. A refusal costs one round trip and
		// names the three ways out; a wrong key costs whoever finds out, whenever
		// they do.
		do {
			_ = try Keystroke.parse("command+delete", readerModifier: .controlOption)
			Issue.record("expected 'command+delete' to be refused")
		} catch let malformed as KeystrokeMalformed {
			#expect(malformed.reason.contains("backspace"))
			#expect(malformed.reason.contains("forwardDelete"))
			#expect(malformed.reason.contains("delete key"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
		// Insert is NVDA's own modifier and a key this keyboard does not have.
		do {
			_ = try Keystroke.parse("control+insert", readerModifier: .controlOption)
			Issue.record("expected 'control+insert' to be refused")
		} catch let malformed as KeystrokeMalformed {
			#expect(malformed.reason.contains("no Insert key"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("the other reader's two modifiers are refused BY NAME, each with its answer")
	func windowsModifiersAreRefusedByName() {
		// An agent that has driven lane 1 writes both of these, and the generic
		// "not a modifier" message would leave it guessing which of five to try.
		do {
			_ = try Keystroke.parse("nvda+f7", readerModifier: .controlOption)
			Issue.record("expected 'nvda+f7' to be refused")
		} catch let malformed as KeystrokeMalformed {
			#expect(malformed.reason.contains("no NVDA key"))
			// SINCE 13.25 IT NAMES THE COUNTERPART RATHER THAN THE KEYS. Before that
			// the message said VoiceOver's modifier is Control-Option unless the
			// person rebound it, and sent the agent to a command name; now there IS
			// a token for the same idea, resolved from the machine, and an agent that
			// wrote `nvda+f7` wants to be told it, not told about two keys that may
			// not be the modifier here at all.
			#expect(malformed.reason.contains("\"vo\""))
			#expect(malformed.reason.contains("vo+m"))
			#expect(!malformed.reason.contains("Control-Option"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
		do {
			_ = try Keystroke.parse("windows+d", readerModifier: .controlOption)
			Issue.record("expected 'windows+d' to be refused")
		} catch let malformed as KeystrokeMalformed {
			#expect(malformed.reason.contains("command"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("a modifier this bridge does not know is refused BY NAME, with the ones it does")
	func unknownModifier() {
		// `cmd` is what an agent that has driven another platform writes.
		// Answering "invalid gesture" would teach it nothing; naming the five
		// modifiers lets it fix the id on the next call.
		for id in ["cmd+l", "meta+l"] {
			do {
				_ = try Keystroke.parse(id, readerModifier: .controlOption)
				Issue.record("expected '\(id)' to be refused")
			} catch let malformed as KeystrokeMalformed {
				#expect(malformed.reason.contains("is not a modifier"))
				#expect(malformed.reason.contains("command"))
				#expect(malformed.reason.contains("option"))
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
	}

	@Test("the KEY GOES LAST, which is lane 1's rule, and the wrong order says so")
	func theKeyGoesLast() {
		// NVDA's `KeyboardInputGesture.fromName` treats the last token as the key,
		// which is why lane 1 carries `press_order` to hoist modifiers to the front.
		// Following it means `command+l` is the same string on both readers in this
		// contract -- and `l+command` is a named failure on both.
		do {
			_ = try Keystroke.parse("l+command", readerModifier: .controlOption)
			Issue.record("expected 'l+command' to be refused")
		} catch let malformed as KeystrokeMalformed {
			#expect(malformed.reason.contains("LAST"))
			#expect(malformed.reason.contains("command+l"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("a multi-character key that names nothing is refused, with the names that exist")
	func unknownKey() {
		for id in ["command+ll", "command+meta", "command+rightarrowkey"] {
			do {
				_ = try Keystroke.parse(id, readerModifier: .controlOption)
				Issue.record("expected '\(id)' to be refused")
			} catch let malformed as KeystrokeMalformed {
				#expect(malformed.reason.contains("neither a single character"))
				#expect(malformed.reason.contains("escape"))
			} catch {
				Issue.record("unexpected error: \(error)")
			}
		}
	}

	@Test("a token that names no key at all is still refused, even with no '+'")
	func aLoneTokenMustStillNameAKey() {
		// 13.19 made a lone key legal here; it did not make a lone WORD legal.
		// `kb:heading` is an agent reaching for a command name through the keyboard
		// source, and the answer is the named failure rather than a press.
		#expect(throws: KeystrokeMalformed.self) { try Keystroke.parse("heading", readerModifier: .controlOption) }
	}

	// -- the canonical spelling ------------------------------------------------

	@Test("`described` is one spelling, and parsing it gives the same keystroke back")
	func describedRoundTrips() throws {
		// It is what the transcript and the `pressed` entry report, so it has to be
		// a spelling this bridge would accept: a record nobody could replay would
		// be a worse record.
		for id in [
			"command+l", "Shift+Command+4", "control+option+space", "command+RETURN", "fn+f5",
			// A lone key round-trips too, which is what makes `kb:h` replayable.
			"h", "downarrow",
		] {
			let keystroke = try Keystroke.parse(id, readerModifier: .controlOption)
			#expect(try Keystroke.parse(keystroke.described, readerModifier: .controlOption) == keystroke)
		}
	}

	@Test("`described` writes the modifiers in one order whatever order they arrived in")
	func describedIsCanonical() throws {
		#expect(try Keystroke.parse("command+shift+4", readerModifier: .controlOption).described == "shift+command+4")
		#expect(try Keystroke.parse("shift+command+4", readerModifier: .controlOption).described == "shift+command+4")
		#expect(try Keystroke.parse("Command+L", readerModifier: .controlOption).described == "command+l")
		#expect(try Keystroke.parse("option+control+space", readerModifier: .controlOption).described == "control+option+space")
	}

	// -- `vo`, the reader's own modifier, which is 13.25 -------------------------

	@Test("`vo` RESOLVES TO THE KEYS THIS MACHINE IS SET TO, and never to a guess")
	func voResolvesFromTheMachine() throws {
		// The whole entry in one assertion: a VoiceOver user presses VO-M, and what
		// goes out is whatever their VO is bound to.
		let pressed = try Keystroke.parse("vo+m", readerModifier: .controlOption)
		#expect(
			pressed
				== Keystroke(
					modifiers: [.control, .option], keys: [.character("m")],
					holdsReaderModifier: true))
	}

	// -- which chords are aimed at the reader, which is 13.29 -------------------

	@Test("AN ORDINARY CHORD IS NOT THE READER's, whatever modifiers it holds")
	func applicationChordsAreNotTheReaders() throws {
		// What the adapter reads to decide whether the event may be stamped, and
		// stamping one of these is what took every application chord away for a
		// week. `control` alone and `option` alone are in the list on purpose: the
		// reader holds BOTH, so half of it is not it.
		for id in ["command+k", "command+shift+a", "control+a", "option+b", "kb:h", "shift+tab"] {
			let bare = id.hasPrefix("kb:") ? String(id.dropFirst(3)) : id
			#expect(
				try Keystroke.parse(bare, readerModifier: .controlOption).holdsReaderModifier
					== false, "\(id) is not aimed at the reader")
		}
	}

	@Test("A CHORD HOLDING THE READER's OWN MODIFIER IS, however it was spelled")
	func readerChordsAreTheReaders() throws {
		// `vo+m` and a literal `control+option+m` are the same keystroke and the
		// same fact -- an agent that spelled the modifier out gets the reader's
		// treatment exactly as one that wrote `vo`. And a chord that holds the
		// reader's modifier AND more is still the reader's: `vo+command+h` is one
		// of its own commands.
		for id in ["vo+m", "control+option+m", "vo+shift+q", "vo+command+h", "control+option+space"] {
			#expect(
				try Keystroke.parse(id, readerModifier: .controlOption).holdsReaderModifier == true,
				"\(id) is aimed at the reader")
		}
	}

	@Test("ON A MACHINE THAT DOES NOT SAY, NOTHING IS THE READER's")
	func anUnreadableModifierClaimsNothing() throws {
		// `control+option` is not the reader's modifier where the person bound it to
		// Caps Lock, so a chord holding it is aimed at whatever has focus -- and
		// where the preference could not be read at all, this bridge does not guess,
		// which is 13.19's rule applied to a second question.
		for setting in [ModifierSetting.capsLock, .unknown] {
			#expect(
				try Keystroke.parse("control+option+m", readerModifier: setting)
					.holdsReaderModifier == false)
		}
	}

	@Test("`either` resolves the same way, because those keys ARE the modifier there")
	func eitherResolvesToTheKeys() throws {
		// "Control-Option or Caps Lock" accepts the two keys, so there is nothing
		// to refuse and nothing to warn about.
		#expect(
			try Keystroke.parse("vo+m", readerModifier: .controlOptionOrCapsLock)
				== Keystroke(
					modifiers: [.control, .option], keys: [.character("m")],
					holdsReaderModifier: true))
	}

	@Test("A CAPS LOCK MACHINE IS A NAMED FAILURE, and the message says what is NOT the answer")
	func capsLockIsRefused() {
		// Pressing control+option here would send two keys that are not the
		// modifier on this machine -- the "wrong keys with total confidence" shape
		// this lane refuses everywhere. And the message has to say so, because
		// `control+option+m` is exactly what an agent reaches for next.
		do {
			_ = try Keystroke.parse("vo+m", readerModifier: .capsLock)
			Issue.record("expected 'vo+m' to be refused on a Caps Lock machine")
		} catch let malformed as KeystrokeMalformed {
			#expect(malformed.reason.contains("CAPS LOCK"))
			#expect(malformed.reason.contains("NOT a substitute"))
			#expect(malformed.reason.contains("command name"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("a machine that would not say is refused too -- `unknown` is not a default")
	func unknownIsRefused() {
		// "I could not look" and "it is at its default" are different facts, and
		// only one of them justifies pressing keys at somebody's screen reader.
		do {
			_ = try Keystroke.parse("vo+m", readerModifier: .unknown)
			Issue.record("expected 'vo+m' to be refused when the binding is unknown")
		} catch let malformed as KeystrokeMalformed {
			#expect(malformed.reason.contains("could not read"))
			#expect(malformed.reason.contains("will not guess"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("`vo` composes with the ordinary modifiers, in either order")
	func voComposes() throws {
		let shifted = try Keystroke.parse("vo+shift+w", readerModifier: .controlOption)
		#expect(shifted.modifiers == [.control, .option, .shift])
		#expect(shifted.keys == [.character("w")])
		// The order among modifiers is not significant, here as everywhere else.
		#expect(try Keystroke.parse("shift+vo+w", readerModifier: .controlOption) == shifted)
	}

	@Test("WHAT IT REPORTS IS THE RESOLVED KEYS, not the symbol it was handed")
	func describedReportsTheResolution() throws {
		// Spec 0052 §3.8: two machines whose `vo` differs must not produce
		// identical transcripts, and the resolved spelling is still replayable.
		#expect(
			try Keystroke.parse("vo+m", readerModifier: .controlOption).described
				== "control+option+m")
	}

	@Test("`vo` on its own is a keystroke with no key, and says so in its own words")
	func voAloneIsRefused() {
		do {
			_ = try Keystroke.parse("vo", readerModifier: .controlOption)
			Issue.record("expected a lone 'vo' to be refused")
		} catch let malformed as KeystrokeMalformed {
			#expect(malformed.reason.contains("needs a key"))
			#expect(malformed.reason.contains("vo+m"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("`vo` AFTER a key is the same named failure `command` is, and not a reordering")
	func voAfterAKeyIsRefused() {
		// It occupies a modifier position, so it has to be refused in one -- the
		// one place not to hide a typo is the one that presses a key.
		do {
			_ = try Keystroke.parse("m+vo", readerModifier: .controlOption)
			Issue.record("expected 'm+vo' to be refused")
		} catch let malformed as KeystrokeMalformed {
			#expect(malformed.reason.contains("may not follow a key"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("a machine that cannot resolve `vo` still presses everything else")
	func otherKeystrokesAreUnaffected() throws {
		// The refusal is about the SYMBOL, not about the machine: `command+l` is
		// the same chord whatever the reader's modifier is bound to, and a bridge
		// that refused it on a Caps Lock machine would have made a much bigger
		// claim than it measured.
		#expect(
			try Keystroke.parse("command+l", readerModifier: .capsLock)
				== Keystroke(modifiers: [.command], keys: [.character("l")]))
		#expect(
			try Keystroke.parse("command+l", readerModifier: .unknown)
				== Keystroke(modifiers: [.command], keys: [.character("l")]))
	}
}
