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
		let keystroke = try Keystroke.parse("command+l")
		#expect(keystroke.modifiers == [.command])
		#expect(keystroke.key == .character("l"))
	}

	@Test("several modifiers, in any order among themselves")
	func modifierOrderDoesNotMatter() throws {
		// A set, not a list -- so the agent does not have to know a convention this
		// bridge never published.
		let written = try Keystroke.parse("shift+command+4")
		let reversed = try Keystroke.parse("command+shift+4")
		#expect(written == reversed)
		#expect(written.modifiers == [.command, .shift])
		#expect(written.key == .character("4"))
	}

	@Test("all five modifiers are known, including fn")
	func everyModifier() throws {
		let keystroke = try Keystroke.parse("fn+control+option+shift+command+t")
		#expect(keystroke.modifiers == [.fn, .control, .option, .shift, .command])
		#expect(keystroke.key == .character("t"))
	}

	@Test("case is not significant")
	func caseIsIgnored() throws {
		// An agent that has read Apple's documentation writes `Command+L`, and it
		// means the same key as `command+l` -- an uppercase letter here is a
		// spelling of the key, not a request for Shift.
		#expect(try Keystroke.parse("Command+L") == Keystroke.parse("command+l"))
		#expect(try Keystroke.parse("CONTROL+Option+Space") == Keystroke.parse("control+option+space"))
	}

	@Test("surrounding whitespace is trimmed, like a command name's")
	func whitespaceIsTrimmed() throws {
		#expect(try Keystroke.parse("  command+l\n") == Keystroke.parse("command+l"))
	}

	// -- named keys ------------------------------------------------------------

	@Test("the named keys are keys, not characters -- they skip the layout entirely")
	func namedKeys() throws {
		// The distinction the adapter depends on: Return is in the same place on
		// every keyboard sold, and `l` is not.
		#expect(try Keystroke.parse("command+enter").key == .named(.enter))
		#expect(try Keystroke.parse("control+escape").key == .named(.escape))
		#expect(try Keystroke.parse("option+forwarddelete").key == .named(.forwardDelete))
		#expect(try Keystroke.parse("command+leftarrow").key == .named(.leftArrow))
		#expect(try Keystroke.parse("command+pagedown").key == .named(.pageDown))
		#expect(try Keystroke.parse("command+space").key == .named(.space))
	}

	// -- a key with no modifiers, which is 13.19 --------------------------------

	@Test("A LONE KEY IS A KEYSTROKE HERE, and that is what `kb:h` means")
	func aLoneKeyParses() throws {
		// The entry's whole point: with single-key Quick Nav on, an ordinary
		// VoiceOver user presses `h` to move by heading. The vocabulary decides
		// that a BARE `h` is one of the reader's command names and that `kb:h` is
		// this -- so by the time an id reaches here, a single token is a key.
		let quickNav = try Keystroke.parse("h")
		#expect(quickNav.modifiers.isEmpty)
		#expect(quickNav.key == .character("h"))
		#expect(try Keystroke.parse("enter") == Keystroke(modifiers: [], key: .named(.enter)))
		#expect(try Keystroke.parse("F5") == Keystroke(modifiers: [], key: .named(.function(5))))
	}

	@Test("f1 through f20, and nothing above f20")
	func functionKeys() throws {
		#expect(try Keystroke.parse("command+f1").key == .named(.function(1)))
		#expect(try Keystroke.parse("control+f20").key == .named(.function(20)))
		// f21 is not a key macOS names, so it is a character token of three
		// characters -- which is a named failure rather than a silent f2.
		#expect(throws: KeystrokeMalformed.self) { try Keystroke.parse("command+f21") }
		#expect(throws: KeystrokeMalformed.self) { try Keystroke.parse("command+f0") }
	}

	@Test("the MAC's spellings are accepted as synonyms for NVDA's names")
	func alternativeSpellings() throws {
		// Each of these is what somebody reading Apple's documentation -- or this
		// bridge's own guidance before 13.19 -- actually types, and each names the
		// same physical key as the canonical spelling beside it. Accepting them
		// costs a line each and saves a round trip that would fail for no good
		// reason. What is NOT accepted is a name that means a DIFFERENT key on the
		// other reader; those are refused below.
		#expect(try Keystroke.parse("command+return").key == .named(.enter))
		#expect(try Keystroke.parse("command+esc").key == .named(.escape))
		#expect(try Keystroke.parse("command+left").key == .named(.leftArrow))
		#expect(try Keystroke.parse("command+down").key == .named(.downArrow))
		#expect(try Keystroke.parse("command+up").key == .named(.upArrow))
		#expect(try Keystroke.parse("command+right").key == .named(.rightArrow))
		// `alt` is `option`: one physical key, two labels, and Apple prints both.
		#expect(try Keystroke.parse("alt+t") == Keystroke.parse("option+t"))
	}

	@Test("EVERY TOKEN ACCEPTED HERE NAMES THE SAME KEY ON NVDA -- spec 0049 §2.3")
	func nvdaNamesAreTheCanonicalOnes() throws {
		// Read out of `../nvda/source/vkCodes.py` at release-2026.1 rather than
		// recalled. Three of these previously spelled themselves in a way that
		// FAILS on lane 1 -- `fromName` looks its tokens up in `vkCodes.byName`,
		// which has `enter`, `leftArrow` and `pageUp` and has never had `return`,
		// `left` or `pageup` -- so a transcript line from this reader could not be
		// replayed on the other one.
		#expect(try Keystroke.parse("command+return").described == "command+enter")
		#expect(try Keystroke.parse("command+left").described == "command+leftArrow")
		#expect(try Keystroke.parse("command+down").described == "command+downArrow")
		#expect(try Keystroke.parse("command+pageup").described == "command+pageUp")
		#expect(try Keystroke.parse("command+backspace").described == "command+backspace")
		#expect(try Keystroke.parse("alt+t").described == "option+t")
	}

	// -- what fails, and by name -----------------------------------------------

	@Test("a missing key is refused, and says what the notation looks like")
	func missingKey() {
		for id in ["command+", "+l", "command++l"] {
			do {
				_ = try Keystroke.parse(id)
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
			_ = try Keystroke.parse("command+delete")
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
			_ = try Keystroke.parse("control+insert")
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
			_ = try Keystroke.parse("nvda+f7")
			Issue.record("expected 'nvda+f7' to be refused")
		} catch let malformed as KeystrokeMalformed {
			#expect(malformed.reason.contains("no NVDA key"))
			#expect(malformed.reason.contains("Control-Option"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
		do {
			_ = try Keystroke.parse("windows+d")
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
				_ = try Keystroke.parse(id)
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
			_ = try Keystroke.parse("l+command")
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
				_ = try Keystroke.parse(id)
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
		#expect(throws: KeystrokeMalformed.self) { try Keystroke.parse("heading") }
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
			let keystroke = try Keystroke.parse(id)
			#expect(try Keystroke.parse(keystroke.described) == keystroke)
		}
	}

	@Test("`described` writes the modifiers in one order whatever order they arrived in")
	func describedIsCanonical() throws {
		#expect(try Keystroke.parse("command+shift+4").described == "shift+command+4")
		#expect(try Keystroke.parse("shift+command+4").described == "shift+command+4")
		#expect(try Keystroke.parse("Command+L").described == "command+l")
		#expect(try Keystroke.parse("option+control+space").described == "control+option+space")
	}
}
