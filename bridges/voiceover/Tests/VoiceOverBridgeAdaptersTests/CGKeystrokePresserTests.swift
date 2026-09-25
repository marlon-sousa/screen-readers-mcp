// Mirrors Sources/VoiceOverBridgeAdapters/CGKeystrokePresser.swift.

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

	@Test("THE KEYCODE COMES FROM THE LAYOUT, which is the whole point of the seam")
	func theKeycodeComesFromTheLayout() throws {
		let layout = FakeKeyboardLayout()
		let poster = FakeEventPoster()
		try presser(layout: layout, poster: poster).press(
			Keystroke(modifiers: [.command], keys: [.character("l")]))

		#expect(layout.asked == ["l"])
		#expect(poster.keyed.map(\.keyCode) == [201, 201])
	}

	@Test("a different layout gives a different key for the same character")
	func aDifferentLayoutMoves() throws {
		let layout = FakeKeyboardLayout(keys: ["l": LayoutKey(keyCode: 250, shifted: false)])
		let poster = FakeEventPoster()
		try presser(layout: layout, poster: poster).press(
			Keystroke(modifiers: [.command], keys: [.character("l")]))
		#expect(poster.keyed.map(\.keyCode) == [250, 250])
	}

	@Test("A NAMED KEY SKIPS THE LAYOUT ENTIRELY")
	func namedKeysSkipTheLayout() throws {
		let layout = FakeKeyboardLayout()
		let poster = FakeEventPoster()
		try presser(layout: layout, poster: poster).press(
			Keystroke(modifiers: [], keys: [.named(.enter)]))

		#expect(layout.asked.isEmpty)
		#expect(poster.keyed.map(\.keyCode) == [0x24, 0x24])
	}

	@Test("every named key has a keycode, and f1 to f20 are not consecutive")
	func everyNamedKeyResolves() throws {
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

	@Test("each modifier becomes its flag")
	func flagsPerModifier() {
		#expect(CGKeystrokePresser.flag(for: .command) == .maskCommand)
		#expect(CGKeystrokePresser.flag(for: .control) == .maskControl)
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
		#expect(CGKeystrokePresser.modifierKeyCodes[.command] == 0x37)
		#expect(CGKeystrokePresser.modifierKeyCodes[.shift] == 0x38)
	}

	@Test("THE WHOLE SEQUENCE: hold, key down, key up, RELEASE")
	func theModifierIsPressedAndReleased() throws {
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [.command], keys: [.character("l")]))

		#expect(
			poster.sequence == [
				.flags(0x37, .maskCommand),
				.key(201, flags: .maskCommand, characters: nil, keyDown: true),
				.key(201, flags: .maskCommand, characters: nil, keyDown: false),
				.flags(0x37, []),
			])
	}

	@Test("several modifiers go down cumulatively and come up in REVERSE, ending at nothing")
	func modifiersNestProperly() throws {
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
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [.command], keys: [.character("$")]))
		#expect(poster.keyed.map(\.keyCode) == [204, 204])
		#expect(poster.keyed.allSatisfy { $0.flags == [.maskCommand, .maskShift] })
		#expect(poster.flagTransitions.last == [])
	}

	@Test("down THEN up, both carrying the flags")
	func downThenUp() throws {
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [.command], keys: [.character("f")]))
		#expect(poster.keyed.count == 2)
		#expect(poster.keyed[0] == .init(keyCode: 202, flags: .maskCommand, characters: nil, keyDown: true))
		#expect(poster.keyed[1] == .init(keyCode: 202, flags: .maskCommand, characters: nil, keyDown: false))
	}

	@Test("TWO KEYS GO DOWN IN ORDER AND COME UP IN REVERSE")
	func twoKeysDownInOrderUpInReverse() throws {
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
		let poster = FakeEventPoster()
		#expect(throws: KeyPressFailure.self) {
			try presser(poster: poster).press(
				Keystroke(modifiers: [], keys: [.character("l"), .character("z")]))
		}
		#expect(poster.sequence.isEmpty)
	}

	@Test("a shifted layer under EITHER key adds the one Shift")
	func aShiftedLayerAnywhereAddsShift() throws {
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [], keys: [.character("l"), .character("$")]))
		#expect(poster.keyed.allSatisfy { $0.flags == .maskShift })
		#expect(poster.flagTransitions == [.maskShift, []])
	}

	@Test("it posts KEY events and never the Unicode shape")
	func itDoesNotType() throws {
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [.command], keys: [.character("l")]))
		#expect(poster.posted.isEmpty)
	}

	@Test("AN UNREACHABLE CHARACTER IS A NAMED FAILURE AND POSTS NOTHING")
	func anUnreachableCharacterPostsNothing() {
		let poster = FakeEventPoster()
		do {
			try presser(poster: poster).press(
				Keystroke(modifiers: [.command], keys: [.character("z")]))
			Issue.record("expected an unreachable character to fail")
		} catch let failure as KeyPressFailure {
			#expect(failure.description.contains("no key that produces"))
			#expect(failure.description.contains("'z'"))
			#expect(failure.description.contains("Nothing was sent"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
		#expect(poster.keyed.isEmpty)
		#expect(poster.posted.isEmpty)
	}

	@Test("a posting failure is reported as the port's own error, not the seam's")
	func aPostingFailureIsTranslated() {
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

	@Test("A KEY EVENT CARRIES THE CHARACTER A REAL KEYPRESS WOULD CARRY")
	func theEventCarriesItsCharacter() throws {
		let poster = FakeEventPoster()
		try presser(poster: poster).press(readerChord([.character("l")]))

		#expect(poster.keyed.map(\.characters) == ["l", "l"])
	}

	@Test("WITH SHIFT HELD IT CARRIES THE SHIFTED LAYER'S CHARACTER")
	func shiftChangesWhatTheEventCarries() throws {
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			readerChord([.character("4")], plus: [.shift]))

		#expect(poster.keyed.map(\.keyCode) == [204, 204])
		#expect(poster.keyed.map(\.characters) == ["$", "$"])
	}

	@Test("a character that BRINGS its own Shift carries the shifted character too")
	func theAddedShiftAlsoChangesTheCharacter() throws {
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			readerChord([.character("$")]))

		#expect(poster.keyed.map(\.characters) == ["$", "$"])
		#expect(poster.keyed.allSatisfy { $0.flags.contains(.maskShift) })
	}

	@Test("ONE SHIFT COVERS EVERY KEY OF A CHORD, exactly as one hand does")
	func theShiftAppliesToEveryKey() throws {
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			readerChord([.character("$"), .character("4")]))

		#expect(poster.keyed.filter(\.keyDown).map(\.characters) == ["$", "$"])
	}

	@Test("A NAMED KEY IS NEVER STAMPED, because the system already fills it")
	func namedKeysAreLeftAlone() throws {
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			Keystroke(modifiers: [], keys: [.named(.leftArrow), .named(.rightArrow)]))

		#expect(poster.keyed.allSatisfy { $0.characters == nil })
	}

	@Test("a layout that will not answer leaves the event as the system built it")
	func anUnstampableKeyStillPresses() throws {
		let layout = FakeKeyboardLayout()
		layout.unstampable = [201]
		let poster = FakeEventPoster()
		try presser(layout: layout, poster: poster).press(readerChord([.character("l")]))

		#expect(poster.keyed.map(\.keyCode) == [201, 201])
		#expect(poster.keyed.allSatisfy { $0.characters == nil })
	}

	@Test("AN APPLICATION CHORD IS LEFT EXACTLY AS THE SYSTEM BUILT IT")
	func applicationChordsAreNeverStamped() throws {
		for chord in [
			Keystroke(modifiers: [.command], keys: [.character("l")]),
			Keystroke(modifiers: [.command, .shift], keys: [.character("l")]),
			Keystroke(modifiers: [.control], keys: [.character("l")]),
			Keystroke(modifiers: [.option], keys: [.character("l")]),
			Keystroke(modifiers: [], keys: [.character("l")]),
		] {
			let poster = FakeEventPoster()
			try presser(poster: poster).press(chord)
			#expect(poster.keyed.allSatisfy { $0.characters == nil })
			#expect(poster.keyed.map(\.keyCode) == [201, 201])
		}
	}

	@Test("CONTROL AND OPTION TOGETHER ARE THE READER's, so that chord IS stamped")
	func readerChordsKeepTheirStamp() throws {
		let poster = FakeEventPoster()
		try presser(poster: poster).press(readerChord([.character("l")]))
		#expect(poster.keyed.allSatisfy { $0.characters == "l" })
	}

	/// A chord aimed at the reader: its own modifiers held, and the flag the parser would have set for it.
	private func readerChord(
		_ keys: [Keystroke.Key], plus extra: Set<Keystroke.Modifier> = []
	) -> Keystroke {
		let readers: Set<Keystroke.Modifier> = [.control, .option]
		return Keystroke(
			modifiers: readers.union(extra), keys: keys, holdsReaderModifier: true)
	}

	@Test("the key-up carries the same character as the key-down")
	func bothHalvesAgree() throws {
		let poster = FakeEventPoster()
		try presser(poster: poster).press(
			readerChord([.character("4")], plus: [.shift]))

		#expect(poster.keyed.count == 2)
		#expect(poster.keyed[0].characters == poster.keyed[1].characters)
		#expect(poster.keyed[0].characters == "$")
	}
}
