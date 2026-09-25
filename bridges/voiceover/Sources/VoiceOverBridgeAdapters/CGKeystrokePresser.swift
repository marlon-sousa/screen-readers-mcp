// ROLE: adapter that implements the KeyPresser port over the KeyboardLayout and EventPoster seams.
// BUILT BY: VoiceOverAdapterFactory.
// USED BY: the PressGesture handler, through the port.
// An unreachable character is a named failure that posts nothing: the key for a character depends on the
// active layout, so the layout is asked and no table of characters exists here.
// Modifiers are pressed and released as `flagsChanged` events: flags alone on the key events left
// `CGEventSource.flagsState` reporting Command held after `command+l`, and every later keystroke was a chord.

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
		// Everything is resolved before anything is posted, so half a chord is never sent.
		let resolved = try keystroke.keys.map(resolve)
		var modifiers = keystroke.modifiers
		// A character on the shifted layer needs a Shift the agent did not ask for; one key needing it is enough.
		if resolved.contains(where: \.shifted) { modifiers.insert(.shift) }
		let held = Keystroke.Modifier.allCases.filter(modifiers.contains)
		let flags = Self.flags(for: modifiers)
		// A keycode event carries the unshifted character whatever its flags, and VoiceOver matches on the
		// character, so `control+option+shift+q` reached VO-Q; the stamp corrects that.
		// Only a chord holding the reader's modifier is stamped: in TextEdit any stamp, even the character already
		// on the event, stopped `command+c` and `command+shift+c` from working.
		let stamped: [String?] =
			keystroke.holdsReaderModifier
			? zip(keystroke.keys, resolved).map {
				stamp($0, resolved: $1, shifted: modifiers.contains(.shift))
			}
			: Array(repeating: nil, count: resolved.count)

		// Swift runs defers in reverse, so the keys come up before the modifiers; both swallow their own failures
		// so the caller's error is never replaced.
		var pressed: [(keyCode: UInt16, characters: String?)] = []
		defer { release(held) }
		defer { releaseKeys(pressed, flags: flags) }
		do {
			try hold(held)
			// Keys are held across each other, not pressed in turn: VoiceOver toggles arrow-key Quick Nav only when
			// both arrows are down together.
			for (key, characters) in zip(resolved, stamped) {
				try poster.post(
					keyCode: key.keyCode, flags: flags, characters: characters, keyDown: true)
				pressed.append((key.keyCode, characters))
			}
		} catch let failure as EventPostingFailure {
			throw KeyPressFailure(failure.description)
		}
	}

	/// Releases only what went down, and cannot throw: a press must never return with a key held.
	private func releaseKeys(_ pressed: [(keyCode: UInt16, characters: String?)], flags: CGEventFlags) {
		for key in pressed.reversed() {
			try? poster.post(
				keyCode: key.keyCode, flags: flags, characters: key.characters, keyDown: false)
		}
	}

	private func hold(_ held: [Keystroke.Modifier]) throws {
		var sofar: CGEventFlags = []
		for modifier in held {
			sofar.insert(Self.flag(for: modifier))
			try poster.postFlagsChanged(keyCode: Self.modifierKeyCodes[modifier] ?? 0, flags: sofar)
		}
	}

	/// Cannot throw, for the same reason as `releaseKeys`.
	private func release(_ held: [Keystroke.Modifier]) {
		var sofar = Self.flags(for: Set(held))
		for modifier in held.reversed() {
			sofar.remove(Self.flag(for: modifier))
			try? poster.postFlagsChanged(keyCode: Self.modifierKeyCodes[modifier] ?? 0, flags: sofar)
		}
	}


	private func resolve(_ key: Keystroke.Key) throws -> LayoutKey {
		switch key {
		case .named(let named):
			guard let keyCode = Self.namedKeyCodes[named] else {
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

	/// A named key is never stamped: the system fills its private-use character correctly.
	private func stamp(_ key: Keystroke.Key, resolved: LayoutKey, shifted: Bool) -> String? {
		guard case .character = key else { return nil }
		return layout.character(forKeyCode: resolved.keyCode, shifted: shifted)
	}

	// Caps Lock is not a modifier here: a synthesized Caps Lock, by every route tried, produced no VoiceOver
	// command and typed the letter, because `maskAlphaShift` only reports the state.

	static func flag(for modifier: Keystroke.Modifier) -> CGEventFlags {
		switch modifier {
		case .command: return .maskCommand
		case .control: return .maskControl
		case .option: return .maskAlternate
		case .shift: return .maskShift
		case .fn: return .maskSecondaryFn
		}
	}

	static func flags(for modifiers: Set<Keystroke.Modifier>) -> CGEventFlags {
		modifiers.reduce(into: CGEventFlags()) { $0.insert(flag(for: $1)) }
	}

	/// The left-hand keys; the system treats either hand's key as the modifier.
	static let modifierKeyCodes: [Keystroke.Modifier: UInt16] = [
		.command: 0x37,
		.shift: 0x38,
		.option: 0x3A,
		.control: 0x3B,
		.fn: 0x3F,
	]

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
		// macOS numbers f1 to f20 non-consecutively.
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
