// Which key produces a character on THIS keyboard, and press a chord with it.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
//     swift scripts/voiceover_chord_press.swift report a l f 4
//     swift scripts/voiceover_chord_press.swift press command a
//     swift scripts/voiceover_chord_press.swift press h
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
let namedKeyCodes: [String: UInt16] = [
	"space": 0x31, "enter": 0x24, "tab": 0x30, "escape": 0x35,
	"backspace": 0x33, "forwarddelete": 0x75,
	"leftarrow": 0x7B, "rightarrow": 0x7C, "downarrow": 0x7D, "uparrow": 0x7E,
]

func postFlagsChanged(keyCode: UInt16, flags: CGEventFlags) {
	guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
		return
	}
	event.type = .flagsChanged
	event.flags = flags
	event.post(tap: .cghidEventTap)
	usleep(30_000)
}

/// Press and release, holding the modifiers as REAL TRANSITIONS.
///
/// FLAGS ALONE ARE NOT ENOUGH, and this file learned it the same way the bridge
/// did: a `command+l` posted with `.maskCommand` on the key events alone delivers
/// the chord and leaves `CGEventSource.flagsState` reporting Command HELD, which
/// makes every keystroke on the machine afterwards a chord. So the modifiers go
/// down as `flagsChanged` events, cumulative, and come back up in reverse ending
/// at nothing -- and the release runs even if the key event could not be made.
func press(keyCode: UInt16, held: [String], flags: CGEventFlags) {
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
	for down in [true, false] {
		guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else {
			FileHandle.standardError.write(Data("could not create a keyboard event\n".utf8))
			return
		}
		event.flags = flags
		event.post(tap: .cghidEventTap)
		usleep(30_000)
	}
}

// -- the two modes ------------------------------------------------------------

var arguments = Array(CommandLine.arguments.dropFirst())
guard let mode = arguments.first else {
	print("usage: report <characters...> | press <modifier...> <key>")
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

case "press":
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
		print("pressing \(arguments.joined(separator: "+")) as keycode \(keyCode) (a named key)")
		press(keyCode: keyCode, held: held, flags: flags)
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
				+ (shifted ? " with an added Shift (it is on the shifted layer here)" : ""))
		press(keyCode: keyCode, held: held, flags: flags)
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
