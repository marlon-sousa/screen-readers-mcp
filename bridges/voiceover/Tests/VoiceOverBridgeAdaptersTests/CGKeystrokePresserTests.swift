// Mirrors Sources/VoiceOverBridgeAdapters/CGKeystrokePresser.swift.
//
// ONE PROPERTY CARRIES MOST OF THIS FILE, and it is board entry 13.17's whole
// risk: THE PRESSER ASKS THE ACTIVE LAYOUT, AND NEVER A TABLE OF ITS OWN. The
// maintainer's keyboard is Brazilian; a hard-coded ANSI table would compile,
// pass every test its author wrote, and press the wrong key on his machine. So
// the fake layout answers with obviously invented keycodes -- if an assertion
// here ever matches a real ANSI value, something has grown a table it should not
// have.
//
// THE SECOND PROPERTY IS THAT AN UNREACHABLE CHARACTER POSTS NOTHING. A chord
// that pressed something else instead would be indistinguishable, from
// everywhere, from a chord the application ignored -- so the failure is named and
// the event stream stays untouched.
//
// THE THIRD ARRIVED FROM A LIVE RUN AND IS THE MOST IMPORTANT: THE KEYBOARD IS
// LEFT CLEAN. The first implementation set modifier FLAGS on the key event and
// posted no transitions, which delivered `command+l` perfectly and left Command
// HELD on the maintainer's machine -- every keystroke afterwards a chord, and
// `typeText` silently typing nothing into an empty field with no error anywhere.
// The tests below assert the whole sequence, in order, including the release, and
// including the release after a FAILED press.

import CoreGraphics
import Fakes
import Testing
import VoiceOverBridgeDomain

@testable import VoiceOverBridgeAdapters

@Suite("CGKeystrokePresser")
struct CGKeystrokePresserTests {
	private func presser(
		layout: FakeKeyboardLayout = FakeKeyboardLayout(),
		poster: FakeEventPoster = FakeEventPoster()
	) -> CGKeystrokePresser {
		CGKeystrokePresser(layout: layout, poster: poster)
	}

	// -- the layout answers, not a table ---------------------------------------

	@Test("THE KEYCODE COMES FROM THE LAYOUT, which is the whole point of the seam")
	func theKeycodeComesFromTheLayout() throws {
		let layout = FakeKeyboardLayout()
		let poster = FakeEventPoster()
		try presser(layout: layout, poster: poster).press(
			Keystroke(modifiers: [.command], keys: [.character("l")]))

		#expect(layout.asked == ["l"])
		// 201 is invented. A presser holding the ANSI constant for `l` would post
		// 37 here and fail.
		#expect(poster.keyed.map(\.keyCode) == [201, 201])
	}

	@Test("a different layout gives a different key for the same character")
	func aDifferentLayoutMoves() throws {
		// What a person switching input sources looks like from here, and the
		// reason the seam is asked per press rather than once.
		let layout = FakeKeyboardLayout(keys: ["l": LayoutKey(keyCode: 250, shifted: false)])
		let poster = FakeEventPoster()
		try presser(layout: layout, poster: poster).press(
			Keystroke(modifiers: [.command], keys: [.character("l")]))
		#expect(poster.keyed.map(\.keyCode) == [250, 250])
	}

	@Test("A NAMED KEY SKIPS THE LAYOUT ENTIRELY")
	func namedKeysSkipTheLayout() throws {
		// Return is in the same place on every keyboard sold, so asking the layout
		// about it would be asking a question with a known answer -- and would make
		// `return` fail on a layout whose reverse map happens not to carry it.
		let layout = FakeKeyboardLayout()
		let poster = FakeEventPoster()
		try presser(layout: layout, poster: poster).press(
			Keystroke(modifiers: [], keys: [.named(.enter)]))

		#expect(layout.asked.isEmpty)
		#expect(poster.keyed.map(\.keyCode) == [0x24, 0x24])
	}

	@Test("every named key has a keycode, and f1 to f20 are not consecutive")
	func everyNamedKeyResolves() throws {
		// The function keys' codes are assigned in an order that is not arithmetic,
		// which is why the adapter carries a literal list -- and this is what stops
		// somebody "simplifying" it into an offset.
		#expect(CGKeystrokePresser.namedKeyCodes[.function(1)] == 0x7A)
		#expect(CGKeystrokePresser.namedKeyCodes[.function(5)] == 0x60)
		#expect(CGKeystrokePresser.namedKeyCodes[.function(20)] == 0x5A)
		for number in 1...Keystroke.NamedKey.highestFunctionKey {
			#expect(CGKeystrokePresser.namedKeyCodes[.function(number)] != nil)
		}
		for key in [
			Keystroke.NamedKey.space, .enter, .tab, .escape, .backspace, .forwardDelete,
			.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end, .pageUp, .pageDown,
		] {
			#expect(CGKeystrokePresser.namedKeyCodes[key] != nil)
		}
	}

	// -- flags -----------------------------------------------------------------

	@Test("each modifier becomes its flag")
	func flagsPerModifier() {
		#expect(CGKeystrokePresser.flag(for: .command) == .maskCommand)
		#expect(CGKeystrokePresser.flag(for: .control) == .maskControl)
		// Option is `.maskAlternate`, which is the one whose name does not match
		// what is written on the key.
		#expect(CGKeystrokePresser.flag(for: .option) == .maskAlternate)
		#expect(CGKeystrokePresser.flag(for: .shift) == .maskShift)
		#expect(CGKeystrokePresser.flag(for: .fn) == .maskSecondaryFn)
		#expect(CGKeystrokePresser.flags(for: []) == [])
	}

	@Test("every modifier has a keycode to press")
	func everyModifierHasAKeyCode() {
		for modifier in Keystroke.Modifier.allCases {
			#expect(CGKeystrokePresser.modifierKeyCodes[modifier] != nil)
		}
		// The left-hand keys, which is a choice rather than an accident -- see the
		// table's own note.
		#expect(CGKeystrokePresser.modifierKeyCodes[.command] == 0x37)
		#expect(CGKeystrokePresser.modifierKeyCodes[.shift] == 0x38)
	}

	// -- the keyboard is left clean ---------------------------------------------

	@Test("THE WHOLE SEQUENCE: hold, key down, key up, RELEASE")
	func theModifierIsPressedAndReleased() throws {
		// The bug this test exists for left Command held on a real machine and made
		// every keystroke afterwards a chord. Flags on the key event deliver the
		// chord and never put the modifier back.
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [.command], keys: [.character("l")]))

		#expect(
			poster.sequence == [
				.flags(0x37, .maskCommand),
				.key(201, flags: .maskCommand, characters: "l", keyDown: true),
				.key(201, flags: .maskCommand, characters: "l", keyDown: false),
				.flags(0x37, []),
			])
	}

	@Test("several modifiers go down cumulatively and come up in REVERSE, ending at nothing")
	func modifiersNestProperly() throws {
		// A `flagsChanged` event carries the state the keyboard is in AFTER it, so
		// the sequence has to build up and unwind -- and the last one must be empty,
		// which is the assertion that says the machine was given back.
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [.command, .shift], keys: [.character("4")]))

		#expect(
			poster.flagTransitions == [
				.maskShift,
				[.maskShift, .maskCommand],
				.maskShift,
				[],
			])
		#expect(poster.flagTransitions.last == [])
	}

	@Test("a keystroke with NO modifiers posts no transitions at all")
	func noModifiersNoTransitions() throws {
		let poster = FakeEventPoster()
		try presser(poster: poster).press(Keystroke(modifiers: [], keys: [.named(.enter)]))
		#expect(poster.flagTransitions.isEmpty)
		#expect(poster.keyed.count == 2)
	}

	@Test("THE MODIFIER IS RELEASED EVEN WHEN THE KEY PRESS FAILED")
	func aFailedPressStillReleases() {
		// The case that would otherwise reproduce the original bug on a failure
		// path: a modifier held for a key that never went out. There is nothing a
		// caller could do about it, and the person at the machine would be left
		// with Command down.
		let poster = FakeEventPoster()
		poster.keyFailure = EventPostingFailure("the system would not create a keyboard event")
		#expect(throws: KeyPressFailure.self) {
			try presser(poster: poster).press(
				Keystroke(modifiers: [.command], keys: [.character("l")]))
		}
		#expect(poster.flagTransitions == [.maskCommand, []])
	}

	@Test("an UNREACHABLE character holds no modifier in the first place")
	func anUnreachableCharacterHoldsNothing() {
		// Everything is resolved before anything is posted, so this fails before the
		// first transition rather than holding Command and then discovering there is
		// no key to press with it.
		let poster = FakeEventPoster()
		#expect(throws: KeyPressFailure.self) {
			try presser(poster: poster).press(
				Keystroke(modifiers: [.command], keys: [.character("z")]))
		}
		#expect(poster.sequence.isEmpty)
	}

	@Test("several modifiers combine into one flag set")
	func flagsCombine() throws {
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [.command, .shift], keys: [.character("4")]))
		#expect(poster.keyed.allSatisfy { $0.flags == [.maskCommand, .maskShift] })
	}

	@Test("A CHARACTER ON THE SHIFTED LAYER ADDS THE SHIFT THE AGENT DID NOT ASK FOR")
	func aShiftedLayerAddsShift() throws {
		// The decision this seam's shape exists for. On a French layout the digits
		// live on the shifted layer, so `command+4` there is really
		// Command-Shift-<that key> -- and a seam that answered only a keycode would
		// have made a chord somebody presses daily a named failure instead.
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [.command], keys: [.character("$")]))
		#expect(poster.keyed.map(\.keyCode) == [204, 204])
		#expect(poster.keyed.allSatisfy { $0.flags == [.maskCommand, .maskShift] })
		// And the added Shift is a real key that is really released, not a flag
		// somebody set: it is held and given back like any other.
		#expect(poster.flagTransitions.last == [])
	}

	// -- down then up ----------------------------------------------------------

	@Test("down THEN up, both carrying the flags")
	func downThenUp() throws {
		// An application that acts on key-down and one that acts on key-up would
		// otherwise disagree about whether the chord happened, and a key-down with
		// no key-up leaves a key held as far as anything watching is concerned.
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [.command], keys: [.character("f")]))
		#expect(poster.keyed.count == 2)
		#expect(poster.keyed[0] == .init(keyCode: 202, flags: .maskCommand, characters: "f", keyDown: true))
		#expect(poster.keyed[1] == .init(keyCode: 202, flags: .maskCommand, characters: "f", keyDown: false))
	}

	// -- two keys held together, which is 13.22 ---------------------------------

	@Test("TWO KEYS GO DOWN IN ORDER AND COME UP IN REVERSE")
	func twoKeysDownInOrderUpInReverse() throws {
		// The sequence the reader's chord detection needs: both keys are DOWN at
		// the same moment, which is what makes it a chord rather than two presses.
		// Measured on 2026-09-01 -- the two arrows sent sequentially move arrow-key
		// Quick Nav not at all, and sent this way they toggle it.
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [], keys: [.named(.leftArrow), .named(.rightArrow)]))

		#expect(
			poster.sequence == [
				.key(0x7B, flags: [], characters: nil, keyDown: true),
				.key(0x7C, flags: [], characters: nil, keyDown: true),
				.key(0x7C, flags: [], characters: nil, keyDown: false),
				.key(0x7B, flags: [], characters: nil, keyDown: false),
			])
	}

	@Test("the modifiers stay held ACROSS both keys, and come up after them")
	func modifiersOutliveTheKeys() throws {
		// The two `defer`s in the order they are registered: the keys come up
		// first and the modifiers after them, which is what a real keyboard does.
		// Releasing Command while a key was still down would be a different chord.
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [.command], keys: [.named(.leftArrow), .named(.rightArrow)]))

		#expect(
			poster.sequence == [
				.flags(0x37, .maskCommand),
				.key(0x7B, flags: .maskCommand, characters: nil, keyDown: true),
				.key(0x7C, flags: .maskCommand, characters: nil, keyDown: true),
				.key(0x7C, flags: .maskCommand, characters: nil, keyDown: false),
				.key(0x7B, flags: .maskCommand, characters: nil, keyDown: false),
				.flags(0x37, []),
			])
	}

	@Test("A CHORD THAT FAILS PARTWAY RELEASES EXACTLY THE KEYS IT PRESSED")
	func aPartialChordReleasesWhatWentDown() {
		// The generalisation of the bug that left Command held on the maintainer's
		// machine: a stuck ordinary key is quieter and just as bad, because every
		// keystroke afterwards repeats it. The first arrow goes down, the second
		// cannot, and the first must come back up -- while the second, which never
		// went down, must NOT get a key-up nothing asked for.
		let poster = FakeEventPoster()
		poster.keyFailure = EventPostingFailure("the system would not create a keyboard event")
		poster.keyFailureAt = 2
		#expect(throws: KeyPressFailure.self) {
			try presser(poster: poster).press(
				Keystroke(modifiers: [.command], keys: [.named(.leftArrow), .named(.rightArrow)]))
		}
		#expect(
			poster.sequence == [
				.flags(0x37, .maskCommand),
				.key(0x7B, flags: .maskCommand, characters: nil, keyDown: true),
				.key(0x7B, flags: .maskCommand, characters: nil, keyDown: false),
				.flags(0x37, []),
			])
	}

	@Test("ONE UNREACHABLE KEY IN A CHORD POSTS NOTHING AT ALL")
	func anUnreachableKeyInAChordPostsNothing() {
		// Everything is resolved before anything is posted, and 13.22 widened
		// "everything" from one key to all of them: pressing the half that works
		// would be a chord nobody asked for, on an edge nobody can watch.
		let poster = FakeEventPoster()
		#expect(throws: KeyPressFailure.self) {
			try presser(poster: poster).press(
				Keystroke(modifiers: [], keys: [.character("l"), .character("z")]))
		}
		#expect(poster.sequence.isEmpty)
	}

	@Test("a shifted layer under EITHER key adds the one Shift")
	func aShiftedLayerAnywhereAddsShift() throws {
		// There is one Shift on a keyboard and one hand holds it, so any key that
		// needs it puts it on the whole chord -- which is also what a person does.
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [], keys: [.character("l"), .character("$")]))
		#expect(poster.keyed.allSatisfy { $0.flags == .maskShift })
		#expect(poster.flagTransitions == [.maskShift, []])
	}

	@Test("it posts KEY events and never the Unicode shape")
	func itDoesNotType() throws {
		// The two shapes of the seam are two different events with two different
		// callers; a chord that arrived as a typed character would insert an `l`
		// into the document instead of opening a location.
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [.command], keys: [.character("l")]))
		#expect(poster.posted.isEmpty)
	}

	// -- the named failure -----------------------------------------------------

	@Test("AN UNREACHABLE CHARACTER IS A NAMED FAILURE AND POSTS NOTHING")
	func anUnreachableCharacterPostsNothing() {
		// The rule the whole entry rests on. `z` is not in the fake layout, which
		// stands for a real layout that has no key for some character an agent
		// asked for -- and the answer to that is a sentence, not a keypress.
		let poster = FakeEventPoster()
		do {
			try presser(poster: poster).press(
				Keystroke(modifiers: [.command], keys: [.character("z")]))
			Issue.record("expected an unreachable character to fail")
		} catch let failure as KeyPressFailure {
			#expect(failure.description.contains("no key that produces"))
			#expect(failure.description.contains("'z'"))
			// It says what state the machine is in, because an agent deciding
			// whether to retry needs to know nothing happened.
			#expect(failure.description.contains("Nothing was sent"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
		#expect(poster.keyed.isEmpty)
		#expect(poster.posted.isEmpty)
	}

	@Test("a posting failure is reported as the port's own error, not the seam's")
	func aPostingFailureIsTranslated() {
		// A seam between two adapters owns its own vocabulary and the adapter above
		// translates -- the same rule `AccessibilityTextTyper` follows.
		let poster = FakeEventPoster()
		poster.failure = EventPostingFailure("the system would not create a keyboard event")
		do {
			try presser(poster: poster).press(
				Keystroke(modifiers: [.command], keys: [.character("l")]))
			Issue.record("expected the posting failure to surface")
		} catch let failure as KeyPressFailure {
			#expect(failure.description.contains("would not create"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	// -- what the event SAYS it is, which is 13.25 ------------------------------

	@Test("A KEY EVENT CARRIES THE CHARACTER A REAL KEYPRESS WOULD CARRY")
	func theEventCarriesItsCharacter() throws {
		// Measured 2026-09-02, and it is a defect this entry fixed rather than a
		// feature it added: a CGEvent built from a keycode carries the UNSHIFTED
		// character whatever flags are set on it. An application never notices --
		// it matches keycode and flags -- and VoiceOver matches on the CHARACTER,
		// so `control+option+shift+q` reached VO-Q, moved a different setting and
		// reported success. Spec 0052 §2.3.
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [.command], keys: [.character("l")]))

		#expect(poster.keyed.map(\.characters) == ["l", "l"])
	}

	@Test("WITH SHIFT HELD IT CARRIES THE SHIFTED LAYER'S CHARACTER")
	func shiftChangesWhatTheEventCarries() throws {
		// The pair that found the defect: the same keycode, the same flags, and the
		// reader reaches a different binding depending on this one field.
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			// `4` and `$` share keycode 204 in the invented layout, `$` on the
			// shifted layer -- so this is the shifted character of the key being
			// pressed, read from the layout rather than upper-cased by hand.
			Keystroke(modifiers: [.shift], keys: [.character("4")]))

		#expect(poster.keyed.map(\.keyCode) == [204, 204])
		#expect(poster.keyed.map(\.characters) == ["$", "$"])
	}

	@Test("a character that BRINGS its own Shift carries the shifted character too")
	func theAddedShiftAlsoChangesTheCharacter() throws {
		// `$` is on the shifted layer, so the presser adds a Shift the agent did
		// not ask for -- and the character has to follow it, or the event would say
		// `4` while Shift was held, which is a keyboard state that cannot happen.
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [.command], keys: [.character("$")]))

		#expect(poster.keyed.map(\.characters) == ["$", "$"])
		#expect(poster.keyed.allSatisfy { $0.flags.contains(.maskShift) })
	}

	@Test("ONE SHIFT COVERS EVERY KEY OF A CHORD, exactly as one hand does")
	func theShiftAppliesToEveryKey() throws {
		// A person holding Shift holds it for both keys. So a chord where one key
		// brought the Shift stamps every character on the shifted layer, rather
		// than each key answering for itself.
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [], keys: [.character("$"), .character("4")]))

		#expect(poster.keyed.filter(\.keyDown).map(\.characters) == ["$", "$"])
	}

	@Test("A NAMED KEY IS NEVER STAMPED, because the system already fills it")
	func namedKeysAreLeftAlone() throws {
		// An arrow's character is a private-use code point this bridge would be
		// inventing rather than reading, and 13.22's arrow chords work today
		// without it. The event only lies about a character key's shifted layer.
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [], keys: [.named(.leftArrow), .named(.rightArrow)]))

		#expect(poster.keyed.allSatisfy { $0.characters == nil })
	}

	@Test("a layout that will not answer leaves the event as the system built it")
	func anUnstampableKeyStillPresses() throws {
		// Nil from the seam is "do not stamp", not a failure: a press that refused
		// here would refuse chords that have always worked, which is a much bigger
		// claim than the measurement supports.
		let layout = FakeKeyboardLayout()
		layout.unstampable = [201]
		let poster = FakeEventPoster()
		try presser(layout: layout, poster: poster).press(
			Keystroke(modifiers: [.command], keys: [.character("l")]))

		#expect(poster.keyed.map(\.keyCode) == [201, 201])
		#expect(poster.keyed.allSatisfy { $0.characters == nil })
	}

	@Test("the key-up carries the same character as the key-down")
	func bothHalvesAgree() throws {
		// The same argument the flags carry: an application that acts on key-up and
		// one that acts on key-down would otherwise disagree about which key it was.
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [.shift], keys: [.character("4")]))

		#expect(poster.keyed.count == 2)
		#expect(poster.keyed[0].characters == poster.keyed[1].characters)
	}
}
