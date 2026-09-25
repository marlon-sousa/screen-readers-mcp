// Which key produces a character on this keyboard, and press a chord with it.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
//     swift scripts/voiceover_chord_press.swift report a l f 4
//     swift scripts/voiceover_chord_press.swift press command a
//     swift scripts/voiceover_chord_press.swift press h
//     swift scripts/voiceover_chord_press.swift press --raw control option shift q
//
// ROLE: the measuring half of `scripts/voiceover_chords.sh`, which owns the scratch document and the safety.
//
// A `CGEvent` carries a virtual keycode, so it asks the live layout which keycode produces a character,
// as the bridge does. `report` presses nothing; `press` and `together` post real events into whatever
// holds focus and need the Accessibility grant. It measures the technique, not the bridge.

import Carbon.HIToolbox
import CoreGraphics
import Foundation

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

/// Unshifted layer first, so a character reachable both ways is reported unshifted.
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

let modifierFlags: [String: CGEventFlags] = [
	"command": .maskCommand, "control": .maskControl, "option": .maskAlternate,
	"shift": .maskShift, "fn": .maskSecondaryFn,
]

/// Copied from `CGKeystrokePresser`.
let modifierKeyCodes: [String: UInt16] = [
	"command": 0x37, "shift": 0x38, "option": 0x3A, "control": 0x3B, "fn": 0x3F,
]

/// Copied from `CGKeystrokePresser`, spelled as NVDA spells them.
var namedKeyCodes: [String: UInt16] = [
	"space": 0x31, "enter": 0x24, "tab": 0x30, "escape": 0x35,
	"backspace": 0x33, "forwarddelete": 0x75,
	"leftarrow": 0x7B, "rightarrow": 0x7C, "downarrow": 0x7D, "uparrow": 0x7E,
	"home": 0x73, "end": 0x77, "pageup": 0x74, "pagedown": 0x79,
]

// Not consecutive; copied from `CGKeystrokePresser`.
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

func character(forKeyCode keyCode: UInt16, shifted: Bool) -> String? {
	guard let layout = layoutData() else { return nil }
	return translate(
		keyCode: keyCode, modifiers: shifted ? UInt32(shiftKey >> 8) : 0, layout: layout)
}

/// Modifiers go down as cumulative `flagsChanged` events and come up in reverse: flags on the key
/// events alone leave `CGEventSource.flagsState` reporting the modifier held afterwards.
///
/// A `CGEvent` built from a keycode carries the unshifted character whatever flags it has, and
/// VoiceOver matches its bindings on the character, so VO-Shift-Q arrives as VO-Q unless the layout's
/// character is stamped with `keyboardSetUnicodeString`. `--raw` skips the stamping as the control.
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

/// Every key down in order, then up in reverse. VoiceOver's arrow-key Quick Nav toggle flips for this
/// and not for the same keys pressed in turn, with or without delay; the `usleep` is for a human watching.
func pressTogether(keyCodes: [UInt16]) {
	for code in keyCodes {
		guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true) else {
			return
		}
		event.post(tap: .cghidEventTap)
		usleep(15_000)
	}
	for code in keyCodes.reversed() {
		guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else {
			return
		}
		event.post(tap: .cghidEventTap)
		usleep(15_000)
	}
}

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
			print("  \(label)NO KEY ON THIS LAYOUT")
		}
	}

case "together":
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
		// The system fills a named key's character; only a character key's shifted layer is wrong.
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
	// A modifier left held makes every later keystroke on the machine a chord.
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
