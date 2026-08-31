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
		#expect(try Keystroke.parse("command+return").key == .named(.return))
		#expect(try Keystroke.parse("control+escape").key == .named(.escape))
		#expect(try Keystroke.parse("option+forwarddelete").key == .named(.forwardDelete))
		#expect(try Keystroke.parse("command+left").key == .named(.left))
		#expect(try Keystroke.parse("command+pagedown").key == .named(.pageDown))
		#expect(try Keystroke.parse("command+space").key == .named(.space))
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

	@Test("the spellings an agent is likely to write are accepted")
	func alternativeSpellings() throws {
		// Each of these is what somebody coming from another platform, or from
		// Apple's own documentation, actually types. Accepting them costs a line
		// each and saves a round trip that would otherwise fail for no good reason.
		#expect(try Keystroke.parse("command+enter").key == .named(.return))
		#expect(try Keystroke.parse("command+esc").key == .named(.escape))
		#expect(try Keystroke.parse("command+backspace").key == .named(.delete))
		#expect(try Keystroke.parse("command+downarrow").key == .named(.down))
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

	@Test("a modifier this bridge does not know is refused BY NAME, with the ones it does")
	func unknownModifier() {
		// `cmd` and `alt` are what an agent that has driven another platform
		// writes. Answering "invalid gesture" would teach it nothing; naming the
		// five modifiers lets it fix the id on the next call.
		for id in ["cmd+l", "alt+t", "meta+l"] {
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

	@Test("an id with no '+' at all is not a keystroke")
	func nothingToSplit() {
		// The vocabulary decides this before `parse` is reached, so this is the
		// entity refusing to invent a chord out of a bare token rather than a case
		// an agent can produce through `pressGesture`.
		#expect(throws: KeystrokeMalformed.self) { try Keystroke.parse("l") }
	}

	// -- the canonical spelling ------------------------------------------------

	@Test("`described` is one spelling, and parsing it gives the same keystroke back")
	func describedRoundTrips() throws {
		// It is what the transcript and the `pressed` entry report, so it has to be
		// a spelling this bridge would accept: a record nobody could replay would
		// be a worse record.
		for id in ["command+l", "Shift+Command+4", "control+option+space", "command+RETURN", "fn+f5"] {
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
