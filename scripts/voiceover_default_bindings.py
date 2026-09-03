# What keys does this reader ship bound to its own commands?
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     python3 scripts/voiceover_default_bindings.py                # every VO chord
#     python3 scripts/voiceover_default_bindings.py --all          # every binding
#     python3 scripts/voiceover_default_bindings.py --grep "menu"  # by command name
#
# ROLE: the versioned instrument behind board entry 13.25's guidance document. It
# reads the KEYS a VoiceOver user presses out of the machine, so that every
# keystroke this repo's guidance names is a measurement rather than something an
# author remembered from Apple's documentation.
#
# IT PRESSES NOTHING, CHANGES NOTHING AND NEEDS NO GRANT. It reads two files that
# ship with macOS and prints a table. Safe to run on any Mac, at any time, with
# the reader running or not.
#
# WHY IT EXISTS. Board entry 13.7 wrote, correctly for what was known then, that
# this document must carry "no table of key combinations for reader commands"
# because a binding is the user's own and unknowable from here. The second half
# turned out to be false: macOS ships the factory bindings in a keyed archive
# beside the command vocabulary, and the two join on the command identifier.
#
#   * SCRStringsToCommandsMap.scrconfig -- 415 English command names, each mapped
#     to an internal identifier ("go to menu bar" -> "SCRWorkspace.goToMenuBar").
#     This is the file the bridge's gesture route already talks to, by name.
#   * ScreenReaderConfiguration.archived-scrconfig -- an NSKeyedArchiver archive
#     whose SCRCConfigurationKeyboardKeyToCommands maps a key SPECIFICATION to the
#     identifiers it runs. The specification is a dictionary, and its fields are
#     the whole notation: `characters`, `commanded` (the VoiceOver modifier is
#     held), `shifted`, `fned`, `function` (the character is a function key), and
#     `pressCount` (2 means a double press).
#
# WHAT IT IS NOT. These are the FACTORY bindings, on this macOS release. A person
# who has rebound a command in VoiceOver Utility's Commanders pane gets their own
# binding, recorded as a deviation in their own preferences, and this script does
# not read that. So a keystroke printed here is what an ordinary machine presses
# and not a promise about a particular one -- which is exactly why the reader's
# own command name stays the diagnosis when a key does nothing.
#
# THE VO MODIFIER IS NOT SPELLED OUT HERE EITHER, and that is deliberate: what
# `commanded` means on a given machine is Control-Option or Caps Lock, read from
# that machine's own preferences. The bridge resolves it (spec 0052); this script
# prints `VO` and leaves it symbolic, which is the same thing the wire notation
# does.

from __future__ import annotations

import argparse
import plistlib
import sys
from pathlib import Path
from plistlib import UID
from typing import Any

RESOURCES = Path("/System/Library/PrivateFrameworks/ScreenReader.framework/Versions/A/Resources")
VOCABULARY = RESOURCES / "SCRStringsToCommandsMap.scrconfig"
CONFIGURATION = RESOURCES / "ScreenReaderConfiguration.archived-scrconfig"

#: The key holding the key-specification to command-identifier map.
BINDINGS_KEY = "SCRCConfigurationKeyboardKeyToCommands"

#: macOS spells the non-typing keys as characters in the Unicode PRIVATE USE
#: area, and these are Apple's own `NSEvent` function-key constants -- the same
#: numbers `AppKit/NSEvent.h` publishes, written as code points rather than as
#: literal characters no editor can show. The names on the right are the bridge's
#: own spellings (spec 0049 §2.3), so a row of this table can be pasted into
#: `press_gesture` as it stands.
SPECIAL_CHARACTERS = {
	chr(0xF700): "upArrow",
	chr(0xF701): "downArrow",
	chr(0xF702): "leftArrow",
	chr(0xF703): "rightArrow",
	chr(0xF727): "insert",
	chr(0xF728): "forwardDelete",
	chr(0xF729): "home",
	chr(0xF72A): "begin",
	chr(0xF72B): "end",
	chr(0xF72C): "pageUp",
	chr(0xF72D): "pageDown",
	chr(0xF739): "clear",
	chr(0xF746): "help",
	# F1 is 0xF704 and they run consecutively to F35.
	**{chr(0xF704 + number - 1): f"f{number}" for number in range(1, 36)},
}

CONTROL_CHARACTERS = {
	"\r": "enter",
	"\n": "enter",
	"\t": "tab",
	"\x1b": "escape",
	"\x7f": "backspace",
	" ": "space",
}


def unarchive(archive: dict[str, Any]) -> Any:
	"""Resolve an NSKeyedArchiver archive into plain Python values.

	Only as much of the format as this file needs: dictionaries and arrays carry
	their contents under `NS.keys` / `NS.objects`, and every other reference is a
	`UID` into the `$objects` table.
	"""
	objects = archive["$objects"]

	def resolve(value: Any) -> Any:
		if isinstance(value, UID):
			return resolve(objects[value.data])
		if isinstance(value, dict):
			if "NS.keys" in value:
				# INDEXED RATHER THAN ZIPPED, on purpose: this script is run with
				# whatever `python3` is on the machine -- which on macOS is the
				# system one -- and `zip(strict=)` is 3.10 and later. The two lists
				# are the same length by the format's own definition.
				items = value["NS.objects"]
				return {
					_hashable(resolve(key)): resolve(items[index])
					for index, key in enumerate(value["NS.keys"])
				}
			if "NS.objects" in value:
				return [resolve(item) for item in value["NS.objects"]]
			return {key: resolve(item) for key, item in value.items() if key != "$class"}
		return value

	return resolve(archive["$top"])


def _hashable(value: Any) -> Any:
	"""A dictionary key that can itself be a dictionary, made usable as one."""
	if isinstance(value, dict):
		return tuple(sorted((key, _hashable(item)) for key, item in value.items()))
	return value


def described(specification: dict[str, object]) -> str:
	"""One key specification, written the way this repository writes a keystroke.

	THE THREE THINGS THIS FORMAT GETS WRONG IF YOU READ IT LITERALLY, each
	established by joining known bindings against Apple's published commands
	rather than by guessing at the field names:

	* **`vo` is implicit.** Every entry in this table belongs to the VoiceOver
	commander, so the modifier is held for all of them and is written on every
	line. Nothing in the dictionary says so; "go to menu bar" is stored as the
	bare character `m` and is VO-M.
	* **`commanded` is the COMMAND key**, not the commander. `Global.findPreviousList`
	is stored commanded with the character `X`, and Apple documents it as
	VO-Command-Shift-X.
	* **Shift is spelled two ways.** A letter or digit carries it in its own CASE
	(`X` is Shift-X); a key with no case -- a function key, an arrow -- carries it
	in the `shifted` flag. Both are written `shift` here.

	`vo` stays symbolic for the reason in the header. The modifier order is the
	bridge's own canonical one, so a line of this table can be pasted into
	`press_gesture` as it stands.
	"""
	name = key_name(specification)
	shifted = bool(specification.get("shifted")) or _is_shifted_character(specification)
	parts: list[str] = []
	if specification.get("fned"):
		parts.append("fn")
	parts.append("vo")
	if specification.get("commanded"):
		parts.append("command")
	if shifted:
		parts.append("shift")
	parts.append(name)
	written = "+".join(parts)
	count = specification.get("pressCount", 1)
	if isinstance(count, int) and count > 1:
		written += f"  (pressed {count} times)"
	return written


def _is_shifted_character(specification: dict[str, object]) -> bool:
	"""Whether the character itself carries the Shift, which is how a LETTER does."""
	characters = str(specification.get("characters") or "")
	return len(characters) == 1 and characters.isupper()


def key_name(specification: dict[str, Any]) -> str:
	characters = str(specification.get("characters") or "")
	if not characters:
		return "<no key>"
	if characters in SPECIAL_CHARACTERS:
		return SPECIAL_CHARACTERS[characters]
	if characters in CONTROL_CHARACTERS:
		return CONTROL_CHARACTERS[characters]
	return characters.lower()


def bindings() -> dict[str, list[str]]:
	"""Command identifier -> the keystrokes bound to it, factory settings."""
	archive = plistlib.loads(CONFIGURATION.read_bytes())
	top = unarchive(archive)
	table = _find(top, BINDINGS_KEY)
	if table is None:
		raise SystemExit(f"{BINDINGS_KEY} is not in {CONFIGURATION}")
	found: dict[str, list[str]] = {}
	for specification, commands in table.items():
		spec = dict(specification) if isinstance(specification, tuple) else specification
		for command in commands:
			found.setdefault(str(command), []).append(described(spec))
	return found


def _find(value: Any, key: str) -> Any:
	"""The first value stored under `key` anywhere in a resolved archive."""
	if isinstance(value, dict):
		if key in value:
			return value[key]
		for item in value.values():
			found = _find(item, key)
			if found is not None:
				return found
	elif isinstance(value, list):
		for item in value:
			found = _find(item, key)
			if found is not None:
				return found
	return None


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--all", action="store_true", help="include commands with no VO modifier")
	parser.add_argument("--grep", default="", help="only command names containing this")
	arguments = parser.parse_args()

	for path in (VOCABULARY, CONFIGURATION):
		if not path.exists():
			print(f"missing {path} -- is this a Mac with VoiceOver?", file=sys.stderr)
			return 1

	vocabulary: dict[str, str] = plistlib.loads(VOCABULARY.read_bytes())
	bound = bindings()

	rows: list[tuple[str, str]] = []
	for name, identifier in sorted(vocabulary.items()):
		keys = bound.get(str(identifier))
		if not keys:
			continue
		if arguments.grep and arguments.grep.lower() not in name.lower():
			continue
		for keystroke in keys:
			if not arguments.all and "vo" not in keystroke.split("+"):
				continue
			rows.append((name, keystroke))

	width = max((len(name) for name, _ in rows), default=0)
	for name, keystroke in rows:
		print(f"{name.ljust(width)}  {keystroke}")
	print(
		f"\n{len(rows)} bindings, out of {len(vocabulary)} command names and "
		f"{sum(len(keys) for keys in bound.values())} factory bindings.",
		file=sys.stderr,
	)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
