// Mirrors Sources/VoiceOverBridgeDomain/Entities/Keystroke.swift.

import Testing

@testable import VoiceOverBridgeDomain

@Suite("Keystroke")
struct KeystrokeTests {
	@Test("the plainest chord there is")
	func commandL() throws {
		let keystroke = try Keystroke.parse("command+l", readerModifier: .controlOption)
		#expect(keystroke.modifiers == [.command])
		#expect(keystroke.keys == [.character("l")])
	}

	@Test("several modifiers, in any order among themselves")
	func modifierOrderDoesNotMatter() throws {
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
		#expect(try Keystroke.parse("Command+L", readerModifier: .controlOption) == Keystroke.parse("command+l", readerModifier: .controlOption))
		#expect(try Keystroke.parse("CONTROL+Option+Space", readerModifier: .controlOption) == Keystroke.parse("control+option+space", readerModifier: .controlOption))
	}

	@Test("surrounding whitespace is trimmed, like a command name's")
	func whitespaceIsTrimmed() throws {
		#expect(try Keystroke.parse("  command+l\n", readerModifier: .controlOption) == Keystroke.parse("command+l", readerModifier: .controlOption))
	}

	@Test("the named keys are keys, not characters -- they skip the layout entirely")
	func namedKeys() throws {
		#expect(try Keystroke.parse("command+enter", readerModifier: .controlOption).keys == [.named(.enter)])
		#expect(try Keystroke.parse("control+escape", readerModifier: .controlOption).keys == [.named(.escape)])
		#expect(try Keystroke.parse("option+forwarddelete", readerModifier: .controlOption).keys == [.named(.forwardDelete)])
		#expect(try Keystroke.parse("command+leftarrow", readerModifier: .controlOption).keys == [.named(.leftArrow)])
		#expect(try Keystroke.parse("command+pagedown", readerModifier: .controlOption).keys == [.named(.pageDown)])
		#expect(try Keystroke.parse("command+space", readerModifier: .controlOption).keys == [.named(.space)])
	}

	@Test("A LONE KEY IS A KEYSTROKE HERE, and that is what `kb:h` means")
	func aLoneKeyParses() throws {
		let quickNav = try Keystroke.parse("h", readerModifier: .controlOption)
		#expect(quickNav.modifiers.isEmpty)
		#expect(quickNav.keys == [.character("h")])
		#expect(try Keystroke.parse("enter", readerModifier: .controlOption) == Keystroke(modifiers: [], keys: [.named(.enter)]))
		#expect(try Keystroke.parse("F5", readerModifier: .controlOption) == Keystroke(modifiers: [], keys: [.named(.function(5))]))
	}

	@Test("TWO ORDINARY KEYS HELD TOGETHER, which is how Quick Nav is toggled")
	func twoKeysTogether() throws {
		let quickNav = try Keystroke.parse("leftarrow+rightarrow", readerModifier: .controlOption)
		#expect(quickNav.modifiers.isEmpty)
		#expect(quickNav.keys == [.named(.leftArrow), .named(.rightArrow)])
	}

	@Test("THE ORDER OF THE KEYS IS KEPT, because it is what down-and-up-in-reverse means")
	func theOrderOfTheKeysIsKept() throws {
		#expect(try Keystroke.parse("rightarrow+leftarrow", readerModifier: .controlOption).keys == [.named(.rightArrow), .named(.leftArrow)])
		#expect(try Keystroke.parse("leftarrow+rightarrow", readerModifier: .controlOption) != Keystroke.parse("rightarrow+leftarrow", readerModifier: .controlOption))
	}

	@Test("modifiers still come first, and they hold across ALL the keys")
	func modifiersHoldAcrossEveryKey() throws {
		let keystroke = try Keystroke.parse("command+leftarrow+rightarrow", readerModifier: .controlOption)
		#expect(keystroke.modifiers == [.command])
		#expect(keystroke.keys == [.named(.leftArrow), .named(.rightArrow)])
	}

	@Test("three keys are no different from two -- there is no cap")
	func threeKeys() throws {
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
		#expect(throws: KeystrokeMalformed.self) { try Keystroke.parse("command+f21", readerModifier: .controlOption) }
		#expect(throws: KeystrokeMalformed.self) { try Keystroke.parse("command+f0", readerModifier: .controlOption) }
	}

	@Test("the MAC's spellings are accepted as synonyms for NVDA's names")
	func alternativeSpellings() throws {
		#expect(try Keystroke.parse("command+return", readerModifier: .controlOption).keys == [.named(.enter)])
		#expect(try Keystroke.parse("command+esc", readerModifier: .controlOption).keys == [.named(.escape)])
		#expect(try Keystroke.parse("command+left", readerModifier: .controlOption).keys == [.named(.leftArrow)])
		#expect(try Keystroke.parse("command+down", readerModifier: .controlOption).keys == [.named(.downArrow)])
		#expect(try Keystroke.parse("command+up", readerModifier: .controlOption).keys == [.named(.upArrow)])
		#expect(try Keystroke.parse("command+right", readerModifier: .controlOption).keys == [.named(.rightArrow)])
		#expect(try Keystroke.parse("alt+t", readerModifier: .controlOption) == Keystroke.parse("option+t", readerModifier: .controlOption))
	}

	@Test("EVERY TOKEN ACCEPTED HERE NAMES THE SAME KEY ON NVDA -- spec 0049 §2.3")
	func nvdaNamesAreTheCanonicalOnes() throws {
		// NVDA 2026.1's `vkCodes.byName` has `enter`, `leftArrow` and `pageUp` but not `return`, `left` or `pageup`, so the canonical spellings follow it.
		#expect(try Keystroke.parse("command+return", readerModifier: .controlOption).described == "command+enter")
		#expect(try Keystroke.parse("command+left", readerModifier: .controlOption).described == "command+leftArrow")
		#expect(try Keystroke.parse("command+down", readerModifier: .controlOption).described == "command+downArrow")
		#expect(try Keystroke.parse("command+pageup", readerModifier: .controlOption).described == "command+pageUp")
		#expect(try Keystroke.parse("command+backspace", readerModifier: .controlOption).described == "command+backspace")
		#expect(try Keystroke.parse("alt+t", readerModifier: .controlOption).described == "option+t")
	}

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
		do {
			_ = try Keystroke.parse("nvda+f7", readerModifier: .controlOption)
			Issue.record("expected 'nvda+f7' to be refused")
		} catch let malformed as KeystrokeMalformed {
			#expect(malformed.reason.contains("no NVDA key"))
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
		#expect(throws: KeystrokeMalformed.self) { try Keystroke.parse("heading", readerModifier: .controlOption) }
	}

	@Test("`described` is one spelling, and parsing it gives the same keystroke back")
	func describedRoundTrips() throws {
		for id in [
			"command+l", "Shift+Command+4", "control+option+space", "command+RETURN", "fn+f5",
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

	@Test("`vo` RESOLVES TO THE KEYS THIS MACHINE IS SET TO, and never to a guess")
	func voResolvesFromTheMachine() throws {
		let pressed = try Keystroke.parse("vo+m", readerModifier: .controlOption)
		#expect(
			pressed
				== Keystroke(
					modifiers: [.control, .option], keys: [.character("m")],
					holdsReaderModifier: true))
	}

	@Test("AN ORDINARY CHORD IS NOT THE READER's, whatever modifiers it holds")
	func applicationChordsAreNotTheReaders() throws {
		for id in ["command+k", "command+shift+a", "control+a", "option+b", "kb:h", "shift+tab"] {
			let bare = id.hasPrefix("kb:") ? String(id.dropFirst(3)) : id
			#expect(
				try Keystroke.parse(bare, readerModifier: .controlOption).holdsReaderModifier
					== false, "\(id) is not aimed at the reader")
		}
	}

	@Test("A CHORD HOLDING THE READER's OWN MODIFIER IS, however it was spelled")
	func readerChordsAreTheReaders() throws {
		for id in ["vo+m", "control+option+m", "vo+shift+q", "vo+command+h", "control+option+space"] {
			#expect(
				try Keystroke.parse(id, readerModifier: .controlOption).holdsReaderModifier == true,
				"\(id) is aimed at the reader")
		}
	}

	@Test("ON A MACHINE THAT DOES NOT SAY, NOTHING IS THE READER's")
	func anUnreadableModifierClaimsNothing() throws {
		for setting in [ModifierSetting.capsLock, .unknown] {
			#expect(
				try Keystroke.parse("control+option+m", readerModifier: setting)
					.holdsReaderModifier == false)
		}
	}

	@Test("`either` resolves the same way, because those keys ARE the modifier there")
	func eitherResolvesToTheKeys() throws {
		#expect(
			try Keystroke.parse("vo+m", readerModifier: .controlOptionOrCapsLock)
				== Keystroke(
					modifiers: [.control, .option], keys: [.character("m")],
					holdsReaderModifier: true))
	}

	@Test("A CAPS LOCK MACHINE IS A NAMED FAILURE, and the message says what is NOT the answer")
	func capsLockIsRefused() {
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
		#expect(try Keystroke.parse("shift+vo+w", readerModifier: .controlOption) == shifted)
	}

	@Test("WHAT IT REPORTS IS THE RESOLVED KEYS, not the symbol it was handed")
	func describedReportsTheResolution() throws {
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
		#expect(
			try Keystroke.parse("command+l", readerModifier: .capsLock)
				== Keystroke(modifiers: [.command], keys: [.character("l")]))
		#expect(
			try Keystroke.parse("command+l", readerModifier: .unknown)
				== Keystroke(modifiers: [.command], keys: [.character("l")]))
	}
}
