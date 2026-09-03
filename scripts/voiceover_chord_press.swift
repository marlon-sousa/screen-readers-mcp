// Which key produces a character on THIS keyboard, and press a chord with it.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
//     swift scripts/voiceover_chord_press.swift report a l f 4
//     swift scripts/voiceover_chord_press.swift press command a
//     swift scripts/voiceover_chord_press.swift press h
//     swift scripts/voiceover_chord_press.swift press --raw control option shift q
//
// ROLE: the measuring half of `scripts/voiceover_chords.sh`, which owns the
// scratch document and the safety. It is a separate file for the reason
// `voiceover_ax_focus.swift` is: the question needs Text Input Services and Core
// Graphics, and a shell cannot ask it.
//
// WHAT IT IS FOR, AND IT IS THE ONE RISK BOARD ENTRY 13.17 WAS WRITTEN AROUND. A
// `CGEvent` carries a VIRTUAL KEYCODE, and which keycode produces `l` depends on
// the layout the person is typing on. A hard-coded ANSI table would compile,
// pass every test its author wrote, and press the wrong key on a Brazilian or a
// French keyboard. So the bridge asks the LIVE LAYOUT through
// `TISCopyCurrentKeyboardInputSource` and `UCKeyTranslate`, and this file asks it
// the same way -- so a maintainer on any layout can see the numbers their own
// machine answers with, rather than taking a test's word for it.
//
// A `press` WITH NO MODIFIERS AT ALL is board entry 13.19's shape -- `kb:h`, the
// letter key an ordinary user presses to move by heading with single-key Quick
// Nav on. Nothing special happens for it here: no modifier goes down, so none has
// to come back up, and the same keycode question is asked of the same layout.
//
// `report` PRESSES NOTHING. It prints the active input source and the keycode
// each character sits on, which is safe to run anywhere and is the half worth
// running first. `press` posts real events into whatever holds focus, which is
// why the shell script around it creates a scratch document, refuses to proceed
// unless that document is frontmost, and closes it without saving on every exit
// path.
//
// IT NEEDS THE ACCESSIBILITY GRANT to press anything, exactly as the bridge does
// -- so this is the counterpart of `voiceover_keyboard.sh` rather than of
// `voiceover_channels.sh`: the gesture probes run on a machine that has never
// granted Accessibility, and this one cannot.
//
// IT IS NOT THE BRIDGE, and must not be read as a test of it. It measures the
// TECHNIQUE on this machine's layout. What checks the bridge's own derivation is
// the live checklist, which drives the real binary over MCP.

import Carbon.HIToolbox
import CoreGraphics
import Foundation

// -- the layout ---------------------------------------------------------------

func inputSourceID() -> String {
	guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
		let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
	else {
		return "<unknown>"
	}
	return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
}

func layoutData() -> CFData? {
	for source in [
		TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
		TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
	] {
		guard let source,
			let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
		else { continue }
		return Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
	}
	return nil
}

func translate(keyCode: UInt16, modifiers: UInt32, layout: CFData) -> String? {
	guard let bytes = CFDataGetBytePtr(layout) else { return nil }
	var deadKeyState: UInt32 = 0
	var length = 0
	var characters = [UniChar](repeating: 0, count: 8)
	let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { pointer in
		UCKeyTranslate(
			pointer, keyCode, UInt16(kUCKeyActionDisplay), modifiers,
			UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
			&deadKeyState, characters.count, &length, &characters)
	}
	guard status == noErr, length > 0 else { return nil }
	return String(utf16CodeUnits: characters, count: length)
}

/// character -> (keycode, is it on the shifted layer). Unshifted layer first, so
/// a character reachable both ways is reported unshifted -- the same rule
/// `CurrentKeyboardLayout` follows.
func reverseMap() -> [Character: (UInt16, Bool)] {
	guard let layout = layoutData() else { return [:] }
	var map: [Character: (UInt16, Bool)] = [:]
	for (shifted, modifiers) in [(false, UInt32(0)), (true, UInt32(shiftKey >> 8))] {
		for keyCode in UInt16(0)...127 {
			guard let produced = translate(keyCode: keyCode, modifiers: modifiers, layout: layout),
				produced.count == 1, let character = produced.first,
				!character.isNewline, map[character] == nil
			else { continue }
			map[character] = (keyCode, shifted)
		}
	}
	return map
}

// -- pressing -----------------------------------------------------------------

let modifierFlags: [String: CGEventFlags] = [
	"command": .maskCommand, "control": .maskControl, "option": .maskAlternate,
	"shift": .maskShift, "fn": .maskSecondaryFn,
]

/// The left-hand modifier keys, by the same table `CGKeystrokePresser` carries.
let modifierKeyCodes: [String: UInt16] = [
	"command": 0x37, "shift": 0x38, "option": 0x3A, "control": 0x3B, "fn": 0x3F,
]

/// The layout-independent keys, by the same table `CGKeystrokePresser` carries.
/// Spelled as NVDA spells them, because the bridge is (spec 0049 §2.3): every
/// name here means the same physical key on the contract's other reader, and
/// `backspace` rather than `delete` is the one that makes that true.
var namedKeyCodes: [String: UInt16] = [
	"space": 0x31, "enter": 0x24, "tab": 0x30, "escape": 0x35,
	"backspace": 0x33, "forwarddelete": 0x75,
	"leftarrow": 0x7B, "rightarrow": 0x7C, "downarrow": 0x7D, "uparrow": 0x7E,
	"home": 0x73, "end": 0x77, "pageup": 0x74, "pagedown": 0x79,
]

// f1 to f20, in the order macOS assigns them -- not consecutive, which is why
// this is a literal list and why it is COPIED FROM `CGKeystrokePresser` rather
// than worked out again. They are here because board entry 13.26's capture probe
// is `vo+f3`, and a probe this file cannot press is one nobody can measure.
let functionKeyCodes: [UInt16] = [
	0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
	0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,
]
for (index, code) in functionKeyCodes.enumerated() {
	namedKeyCodes["f\(index + 1)"] = code
}

func postFlagsChanged(keyCode: UInt16, flags: CGEventFlags) {
	guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
		return
	}
	event.type = .flagsChanged
	event.flags = flags
	event.post(tap: .cghidEventTap)
	usleep(30_000)
}

/// The character a keycode produces on THIS layout, on the layer asked for.
///
/// The forward question, where `reverseMap` asks the backward one. It exists for
/// the stamping below and for nothing else.
func character(forKeyCode keyCode: UInt16, shifted: Bool) -> String? {
	guard let layout = layoutData() else { return nil }
	return translate(
		keyCode: keyCode, modifiers: shifted ? UInt32(shiftKey >> 8) : 0, layout: layout)
}

/// Press and release, holding the modifiers as REAL TRANSITIONS.
///
/// FLAGS ALONE ARE NOT ENOUGH, and this file learned it the same way the bridge
/// did: a `command+l` posted with `.maskCommand` on the key events alone delivers
/// the chord and leaves `CGEventSource.flagsState` reporting Command HELD, which
/// makes every keystroke on the machine afterwards a chord. So the modifiers go
/// down as `flagsChanged` events, cumulative, and come back up in reverse ending
/// at nothing -- and the release runs even if the key event could not be made.
///
/// ============================================================================
/// AND THE EVENT HAS TO CARRY THE RIGHT CHARACTER -- MEASURED 2026-09-02.
/// ============================================================================
///
/// A `CGEvent` built from a keycode carries the UNSHIFTED character whatever
/// flags are set on it and whatever Shift transitions were posted before it:
/// keycode 12 with Control, Option and Shift held carries `q`, not `Q`. That is
/// invisible to an application, which matches the keycode and the flags -- and it
/// is NOT invisible to VoiceOver, which matches its own bindings on the
/// CHARACTER. So the same chord that a person presses as VO-Shift-Q arrived as
/// VO-Q and toggled the WRONG setting, reporting success throughout:
///
///     control+option+shift+q, event carrying 'q'  -> single-key Quick Nav moved
///     control+option+shift+q, event carrying 'Q'  -> arrow-key Quick Nav moved
///
/// So the character the active layout produces on the requested layer is stamped
/// onto the event with `keyboardSetUnicodeString`, which is what a real keypress
/// carries. `--raw` skips the stamping, and exists so the measurement above stays
/// re-runnable: it is the control that shows the stamping is what makes the
/// difference, and nothing else should use it.
func press(keyCode: UInt16, held: [String], flags: CGEventFlags, stamp: Bool = true) {
	var sofar: CGEventFlags = []
	for modifier in held {
		sofar.insert(modifierFlags[modifier] ?? [])
		postFlagsChanged(keyCode: modifierKeyCodes[modifier] ?? 0, flags: sofar)
	}
	defer {
		var remaining = sofar
		for modifier in held.reversed() {
			remaining.remove(modifierFlags[modifier] ?? [])
			postFlagsChanged(keyCode: modifierKeyCodes[modifier] ?? 0, flags: remaining)
		}
	}
	let stamped = stamp ? character(forKeyCode: keyCode, shifted: flags.contains(.maskShift)) : nil
	for down in [true, false] {
		guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else {
			FileHandle.standardError.write(Data("could not create a keyboard event\n".utf8))
			return
		}
		event.flags = flags
		if let stamped {
			var units = Array(stamped.utf16)
			event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
		}
		event.post(tap: .cghidEventTap)
		usleep(30_000)
	}
}

/// Press several ORDINARY keys at the same time: every key down in order, then
/// every key up in reverse -- which is what a real keyboard produces when
/// somebody holds two keys at once.
///
/// SEPARATE FROM `press` BECAUSE THE SHAPE IS DIFFERENT, not because the code
/// is. `press` holds MODIFIERS, whose transitions are `flagsChanged` events and
/// whose whole subtlety is the flags (spec 0048 §2.5). There are no flags here:
/// Left Arrow and Right Arrow are ordinary keys, and "together" is expressed
/// entirely by the ORDER of the downs and ups.
///
/// MEASURED 2026-09-01, and this function is the instrument that measured it:
/// VoiceOver's arrow-key Quick Nav toggle -- which a person presses as Left and
/// Right together -- flips for this sequence and does NOT flip for the same two
/// keys pressed one after the other. So the reader really is detecting
/// simultaneity, and a synthesized chord satisfies it.
///
/// NO DELAY IS NEEDED BETWEEN THE EVENTS, also measured: posting the four events
/// back to back toggles it exactly as a 15 ms spacing does. The `usleep` below is
/// therefore for the HUMAN watching a probe run, not for the reader.
func pressTogether(keyCodes: [UInt16]) {
	for code in keyCodes {
		guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true) else {
			return
		}
		event.post(tap: .cghidEventTap)
		usleep(15_000)
	}
	// RELEASED IN REVERSE, like a hand coming off the keyboard. It is also the
	// safe order: the last key down is the first released, so nothing is left
	// held if a post fails partway.
	for code in keyCodes.reversed() {
		guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else {
			return
		}
		event.post(tap: .cghidEventTap)
		usleep(15_000)
	}
}

// -- the three modes ----------------------------------------------------------

var arguments = Array(CommandLine.arguments.dropFirst())
guard let mode = arguments.first else {
	print("usage: report <characters...> | press [--raw] <modifier...> <key> | together <key> <key...>")
	exit(2)
}
arguments.removeFirst()

switch mode {
case "report":
	print("input source        \(inputSourceID())")
	let map = reverseMap()
	print("characters mapped   \(map.count)")
	for token in arguments {
		guard let character = token.first, token.count == 1 else {
			print("  \(token.padding(toLength: 18, withPad: " ", startingAt: 0))not a single character")
			continue
		}
		let label = String(character).padding(toLength: 18, withPad: " ", startingAt: 0)
		if let (keyCode, shifted) = map[character] {
			print("  \(label)keycode \(keyCode)\(shifted ? "  (on the SHIFTED layer)" : "")")
		} else {
			// The named failure, seen from outside: this is what the bridge reports
			// rather than pressing something else.
			print("  \(label)NO KEY ON THIS LAYOUT")
		}
	}

case "together":
	// Ordinary keys only: a modifier here would be a `press`, and mixing the two
	// notations in one probe would make a failure ambiguous between them.
	guard arguments.count >= 2 else {
		print("together needs at least two named keys")
		exit(2)
	}
	var codes: [UInt16] = []
	for token in arguments {
		guard let code = namedKeyCodes[token.lowercased()] else {
			print("'\(token)' is not a named key this probe knows: \(namedKeyCodes.keys.sorted())")
			exit(2)
		}
		codes.append(code)
	}
	print("pressing \(arguments.joined(separator: "+")) TOGETHER as keycodes \(codes)")
	pressTogether(keyCodes: codes)

case "press":
	// `--raw` is the CONTROL for the stamping measurement above, and nothing else
	// should use it: it posts the event exactly as this file did before 13.25,
	// carrying the unshifted character.
	var stamp = true
	if let first = arguments.first, first == "--raw" {
		stamp = false
		arguments.removeFirst()
	}
	guard let keyToken = arguments.last else {
		print("press needs a key")
		exit(2)
	}
	var flags: CGEventFlags = []
	var held: [String] = []
	for modifier in arguments.dropLast() {
		guard let flag = modifierFlags[modifier] else {
			print("unknown modifier: \(modifier)")
			exit(2)
		}
		flags.insert(flag)
		held.append(modifier)
	}
	if let keyCode = namedKeyCodes[keyToken] {
		// NOT STAMPED, deliberately. A named key is layout-independent and the
		// system already fills its character (an arrow is a private-use code point
		// this file has no business inventing); the stamping exists for the SHIFTED
		// LAYER of a character key, which is the only place the event lies.
		print("pressing \(arguments.joined(separator: "+")) as keycode \(keyCode) (a named key)")
		press(keyCode: keyCode, held: held, flags: flags, stamp: false)
	} else {
		guard let character = keyToken.first, keyToken.count == 1 else {
			print("\(keyToken) is neither a single character nor a named key")
			exit(2)
		}
		guard let (keyCode, shifted) = reverseMap()[character] else {
			print("THIS LAYOUT HAS NO KEY THAT PRODUCES '\(character)'. Nothing was sent.")
			exit(3)
		}
		if shifted {
			flags.insert(.maskShift)
			held.append("shift")
		}
		print(
			"pressing \(arguments.joined(separator: "+")) as keycode \(keyCode)"
				+ (shifted ? " with an added Shift (it is on the shifted layer here)" : "")
				+ (stamp ? "" : "  [--raw: the event carries the UNSHIFTED character]"))
		press(keyCode: keyCode, held: held, flags: flags, stamp: stamp)
	}
	// PROVE THE KEYBOARD IS CLEAN, because the whole reason this file posts
	// transitions is that the first version did not and left Command down.
	usleep(200_000)
	let state = CGEventSource.flagsState(.combinedSessionState)
	let stuck = modifierFlags.filter { state.contains($0.value) }.keys.sorted()
	if stuck.isEmpty {
		print("modifiers after the press: none held")
	} else {
		print("*** MODIFIERS STILL HELD: \(stuck.joined(separator: ", ")) -- press and release")
		print("*** them on the keyboard before typing anything else.")
		exit(4)
	}

default:
	print("unknown mode: \(mode)")
	exit(2)
}
