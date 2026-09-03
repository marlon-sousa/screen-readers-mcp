// ROLE: adapter -- IMPLEMENTS the KeyPresser domain port, over the
// KeyboardLayout and EventPoster seams.
//
// BUILT BY: VoiceOverAdapterFactory. USED BY: the PressGesture handler, through
// the port, on a gesture id written as a keystroke.
//
// IT HOLDS EVERY DECISION ON THIS EDGE: which keycode a named key is, what a
// modifier does to the event's flags, what a shifted layer adds, in what order
// the two halves go out, and what happens when the layout has no key for a
// character. Below it, `CurrentKeyboardLayout` reads the system's answer and
// `CGEventPoster` builds one event -- neither decides anything.
//
// ============================================================================
// AN UNREACHABLE CHARACTER IS A NAMED FAILURE AND POSTS NOTHING.
// ============================================================================
//
// That is the rule this class exists to enforce, and it is spec 0048 §2.4's
// whole point. Which key produces `l` depends on the active layout, and the
// maintainer's is Brazilian: a hard-coded ANSI table would pass review, pass
// every test its author wrote, and press the WRONG KEY on his machine. So there
// is no table of characters here at all -- the layout is asked, and if it has no
// answer the press fails saying so. "This layout has no key that produces `\`"
// is something an agent can act on; pressing something else is not, and a chord
// that quietly did the wrong thing is the worst failure available on an edge
// nobody can watch.
//
// NOTHING IS POSTED BEFORE EVERY KEYCODE IS KNOWN, which is why the whole
// keystroke is resolved before the first event. Half a chord -- a key-down with
// no key-up, or a modifier flag on an event that never arrives -- would leave
// whatever watches the event stream believing a key is still held. Since 13.22 a
// keystroke may carry SEVERAL keys, so "the whole keystroke" means all of them:
// `leftArrow+rightArrow` with one key unreachable posts nothing at all rather
// than pressing the half it can.
//
// NAMED KEYS SKIP THE LAYOUT ENTIRELY, and the table below is theirs. Return is
// in the same place on every keyboard sold, so these are constants rather than
// questions -- and having them here rather than behind the layout seam keeps the
// seam answering only what genuinely varies. It is also why they are the ONE
// table this file is allowed to contain: a physical position is not a layout.
//
// ============================================================================
// THE MODIFIERS ARE PRESSED AND RELEASED, NOT MERELY SET AS FLAGS.
// ============================================================================
//
// Spec 0048 §2.5 said flags on the key event and no separate modifier events,
// "until something measured needs more". Something measured needed more within
// the hour, and it is the sharpest bug this entry produced.
//
// FLAGS ALONE DELIVER THE CHORD AND NEVER PUT THE MODIFIER BACK. Measured live
// on 2026-08-31: one `command+l` posted with `.maskCommand` on the key-down and
// the key-up opened Safari's location bar exactly as intended -- and left
// `CGEventSource.flagsState(.combinedSessionState)` reporting **Command held**.
// Every keystroke on that machine afterwards was a chord. `typeText` posted its
// characters and nothing arrived anywhere, silently, because each one was a
// Command-chord; the first symptom was an empty text field and no error at all.
//
// That is not an app-compatibility nicety. It is somebody's own keyboard left in
// a state they did not put it in, by a bridge whose Rule 0 is that it gives the
// machine back. So the sequence is what a real keyboard produces:
//
//   1. a `flagsChanged` per modifier, in a fixed order, each carrying the
//      CUMULATIVE state so far -- which is what such an event means
//   2. every key down IN ORDER, then every key up IN REVERSE, all carrying the
//      full flags -- one key each way for `command+l`, two for
//      `leftArrow+rightArrow`, which is the chord being simultaneous rather than
//      sequential (13.22)
//   3. a `flagsChanged` per modifier in REVERSE, each carrying the state with
//      that modifier removed, ending at `[]`
//
// AND STEPS 2's RELEASE AND STEP 3 RUN EVEN WHEN THE PRESS FAILED, in that
// order, which is why there are two `defer`s and why the keys' one is registered
// second. A press that threw half-way through
// would otherwise leave exactly the state this section is about, so the release
// is in a `defer` and its own failures are swallowed: there is nothing a caller
// could usefully do with "the chord failed AND the release failed", and reporting
// the second in place of the first would hide the one that matters. Leaving a
// person's Command key down is worse than any error this class could return.
//
// A `voiceover_modifiers.sh`-style ASSERTION IS WHAT WOULD HAVE CAUGHT IT, and
// that script's header had warned about exactly this hazard for a day: "a sticky
// modifier that stays down would make every subsequent keystroke on the machine a
// chord". `scripts/voiceover_chords.sh` now proves the keyboard is clean after
// the chord, the same way.

import CoreGraphics
import VoiceOverBridgeDomain

public final class CGKeystrokePresser: KeyPresser {
	private let layout: any KeyboardLayout
	private let poster: any EventPoster

	public init(layout: any KeyboardLayout, poster: any EventPoster) {
		self.layout = layout
		self.poster = poster
	}

	public func press(_ keystroke: Keystroke) throws {
		// EVERYTHING IS RESOLVED BEFORE ANYTHING IS POSTED. Half a chord -- a
		// modifier held for a key that turned out to be unreachable, or the first
		// of two keys down and the second unpressable -- is the state this class
		// exists to prevent.
		let resolved = try keystroke.keys.map(resolve)
		var modifiers = keystroke.modifiers
		// A character on the shifted layer needs the Shift the agent did not ask
		// for: on a French layout the digits live there, so `command+4` is really
		// Command-Shift-<that key>. The seam reports the layer; the decision to add
		// it is this line, above it. ANY of the keys needing it is enough, which is
		// also what a person's hand does -- there is one Shift.
		if resolved.contains(where: \.shifted) { modifiers.insert(.shift) }
		let held = Keystroke.Modifier.allCases.filter(modifiers.contains)
		let flags = Self.flags(for: modifiers)
		// WHAT EACH EVENT WILL SAY IT IS -- 13.25, and it is decided HERE because
		// it is a decision. A CGEvent built from a keycode carries the UNSHIFTED
		// character whatever flags are on it; an application never notices, and
		// this reader matches on the character, so `control+option+shift+q` used to
		// reach VO-Q rather than VO-Shift-Q and say it had succeeded (spec 0052
		// §2.3). The Shift in force is the one computed just above -- asked for, or
		// added because a key sits on the shifted layer -- so a chord that acquires
		// a Shift for one of its keys stamps every character on the shifted layer,
		// which is what one hand on one Shift key produces.
		let stamped = zip(keystroke.keys, resolved).map {
			stamp($0, resolved: $1, shifted: modifiers.contains(.shift))
		}

		// TWO DEFERS, AND THEIR ORDER IS THE POINT. Swift runs them in reverse, so
		// the keys come up first and the modifiers after them -- which is what a
		// real keyboard does, and the opposite would release Command while `l` was
		// still down. Both run whatever happened below, and both swallow their own
		// failures rather than replacing the caller's error; see the header.
		var pressed: [(keyCode: UInt16, characters: String?)] = []
		defer { release(held) }
		defer { releaseKeys(pressed, flags: flags) }
		do {
			try hold(held)
			// DOWN IN ORDER, UP IN REVERSE, ALL CARRYING THE FLAGS, exactly as
			// `AccessibilityTextTyper` sends both halves of a typed chunk: an
			// application that acts on key-down and one that acts on key-up would
			// otherwise disagree about whether the chord happened, and a key-down
			// with no key-up leaves a key held as far as anything watching is
			// concerned. The keys are HELD across each other and not pressed one
			// after another, because simultaneity is what the reader detects --
			// measured 2026-09-01: the two arrows sent sequentially move nothing,
			// and sent together they toggle arrow-key Quick Nav. No delay between
			// the events is needed.
			for (key, characters) in zip(resolved, stamped) {
				try poster.post(
					keyCode: key.keyCode, flags: flags, characters: characters, keyDown: true)
				pressed.append((key.keyCode, characters))
			}
		} catch let failure as EventPostingFailure {
			throw KeyPressFailure(failure.description)
		}
	}

	/// Release the keys that actually went down, in reverse, so a press that
	/// failed partway leaves nothing held.
	///
	/// IT CANNOT THROW, for the reason `release` cannot: a key-up that failed
	/// would be reported in place of the failure that matters, and what there must
	/// not be is a `press` that returns with a key down. It releases exactly what
	/// was pressed rather than everything that was asked for -- a key-down that
	/// never went out needs no key-up, and posting one would tell whatever is
	/// watching about a keystroke that never happened.
	private func releaseKeys(_ pressed: [(keyCode: UInt16, characters: String?)], flags: CGEventFlags) {
		for key in pressed.reversed() {
			try? poster.post(
				keyCode: key.keyCode, flags: flags, characters: key.characters, keyDown: false)
		}
	}

	/// Press the modifiers, one transition at a time, each carrying the state the
	/// keyboard is in after it.
	private func hold(_ held: [Keystroke.Modifier]) throws {
		var sofar: CGEventFlags = []
		for modifier in held {
			sofar.insert(Self.flag(for: modifier))
			try poster.postFlagsChanged(keyCode: Self.modifierKeyCodes[modifier] ?? 0, flags: sofar)
		}
	}

	/// Release them in reverse, ending at no modifiers held at all.
	///
	/// IT CANNOT THROW, and that is deliberate rather than lazy -- see the header.
	/// A release that failed would be reported in place of the failure that
	/// actually matters, and there is nothing a caller could do about it either
	/// way; what there must not be is a `press` that returns with a modifier down.
	private func release(_ held: [Keystroke.Modifier]) {
		var sofar = Self.flags(for: Set(held))
		for modifier in held.reversed() {
			sofar.remove(Self.flag(for: modifier))
			try? poster.postFlagsChanged(keyCode: Self.modifierKeyCodes[modifier] ?? 0, flags: sofar)
		}
	}

	// -- the decisions -----------------------------------------------------------

	/// Which key to press, or why this machine cannot press it.
	private func resolve(_ key: Keystroke.Key) throws -> LayoutKey {
		switch key {
		case .named(let named):
			guard let keyCode = Self.namedKeyCodes[named] else {
				// Unreachable while the table covers the enumeration, and a named
				// failure rather than a crash if a future case is added without one.
				throw KeyPressFailure(
					"this bridge has no keycode for the '\(named.described)' key")
			}
			return LayoutKey(keyCode: keyCode, shifted: false)
		case .character(let character):
			guard let found = layout.key(for: character) else {
				throw KeyPressFailure(
					"the keyboard layout active on this machine has no key that produces "
						+ "'\(character)', so there is no chord to press. Nothing was sent. Try a key "
						+ "this layout does have, or one of the named keys (enter, tab, escape, the "
						+ "arrows, f1 to f20), or ask the person at the machine which key it is on")
			}
			return found
		}
	}

	/// The characters one resolved key should carry, or nil to leave the event as
	/// the system built it.
	///
	/// A NAMED KEY IS NEVER STAMPED, and that is the second half of the decision.
	/// An arrow or a function key is layout-independent, its character is a
	/// private-use code point (`\u{F702}` for Left Arrow) that this bridge would
	/// be inventing rather than reading, and the system fills it correctly -- which
	/// is why 13.22's arrow chords work today. The event only lies about the
	/// SHIFTED LAYER of a character key, so that is the only thing corrected.
	private func stamp(_ key: Keystroke.Key, resolved: LayoutKey, shifted: Bool) -> String? {
		guard case .character = key else { return nil }
		return layout.character(forKeyCode: resolved.keyCode, shifted: shifted)
	}

	/// The flag one modifier sets.
	///
	/// `fn` is `.maskSecondaryFn`, which is the flag the window server sets for a
	/// laptop's Fn key; the other four are the flags every menu shortcut is
	/// matched against. Option is `.maskAlternate`, which is the one whose name
	/// does not match what is written on the key.
	static func flag(for modifier: Keystroke.Modifier) -> CGEventFlags {
		switch modifier {
		case .command: return .maskCommand
		case .control: return .maskControl
		case .option: return .maskAlternate
		case .shift: return .maskShift
		case .fn: return .maskSecondaryFn
		}
	}

	/// The flags for a set of modifiers.
	static func flags(for modifiers: Set<Keystroke.Modifier>) -> CGEventFlags {
		modifiers.reduce(into: CGEventFlags()) { $0.insert(flag(for: $1)) }
	}

	/// The LEFT-HAND modifier keys, by their `kVK_` constants.
	///
	/// Left rather than right, and it is a choice rather than an accident: a
	/// keyboard has two of most of these and the system treats either as the
	/// modifier, so one has to be picked and the left one is what a person's hand
	/// reaches by default. They are layout-independent constants, exactly as the
	/// named keys above are, and for the same reason.
	static let modifierKeyCodes: [Keystroke.Modifier: UInt16] = [
		.command: 0x37,
		.shift: 0x38,
		.option: 0x3A,
		.control: 0x3B,
		.fn: 0x3F,
	]

	/// The keys whose position is the same on every keyboard.
	///
	/// These are the `kVK_` constants, written out rather than imported from
	/// Carbon so that this table reads as what it is -- and so that the one file
	/// in this bridge that talks to Text Input Services stays the leaf below.
	static let namedKeyCodes: [Keystroke.NamedKey: UInt16] = {
		var codes: [Keystroke.NamedKey: UInt16] = [
			.space: 0x31,
			.enter: 0x24,
			.tab: 0x30,
			.escape: 0x35,
			.backspace: 0x33,
			.forwardDelete: 0x75,
			.leftArrow: 0x7B,
			.rightArrow: 0x7C,
			.downArrow: 0x7D,
			.upArrow: 0x7E,
			.home: 0x73,
			.end: 0x77,
			.pageUp: 0x74,
			.pageDown: 0x79,
		]
		// f1 to f20, in the order macOS assigns them -- which is not consecutive
		// and is why this is a literal list rather than arithmetic.
		let functionKeys: [UInt16] = [
			0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
			0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,
		]
		for (index, keyCode) in functionKeys.enumerated() {
			codes[.function(index + 1)] = keyCode
		}
		return codes
	}()
}
