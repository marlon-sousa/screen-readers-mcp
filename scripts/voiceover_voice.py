#!/usr/bin/env python3
# Read and set VoiceOver's selected voice, by preference.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     python3 scripts/voiceover_voice.py show
#     python3 scripts/voiceover_voice.py set com.apple.eloquence.pt-BR.Reed
#
# ROLE: points VoiceOver at the bridge's capture voice, and back, without a human.
#
# The store is VoiceOverDefaultVoiceSelections in ~/Library/Preferences/com.apple.SpeakSelection.plist,
# not VoiceOver's own preferences; a change applies live, with no reader restart.
# Written through export and import because `defaults write` makes `pitch` and `rate` strings, and
# VoiceOver then silently rejects the record and overwrites the key with its own choice.

from __future__ import annotations

import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

DOMAIN = "com.apple.SpeakSelection"
KEY = "VoiceOverDefaultVoiceSelections"
ENTRY_TYPE = "Speech.VoiceSelection"


def _export() -> dict[str, object]:
	path = Path(tempfile.mktemp(suffix=".plist"))
	subprocess.run(["defaults", "export", DOMAIN, str(path)], check=True)
	try:
		with path.open("rb") as handle:
			return plistlib.load(handle)
	finally:
		path.unlink(missing_ok=True)


def _import(data: dict[str, object]) -> None:
	path = Path(tempfile.mktemp(suffix=".plist"))
	try:
		with path.open("wb") as handle:
			plistlib.dump(data, handle)
		subprocess.run(["defaults", "import", DOMAIN, str(path)], check=True)
	finally:
		path.unlink(missing_ok=True)


def _selections(data: dict[str, object]) -> list[dict[str, object]]:
	entries = data.get(KEY)
	if not isinstance(entries, list):
		raise SystemExit(f"{DOMAIN} has no {KEY}. Select a voice by hand once to create it.")
	return [e for e in entries if isinstance(e, dict) and e.get("_type") == ENTRY_TYPE]


def show() -> int:
	for entry in _selections(_export()):
		print(entry.get("voiceId", "<none>"))
	return 0


def set_voice(voice_id: str) -> int:
	data = _export()
	selections = _selections(data)
	if not selections:
		raise SystemExit(f"no {ENTRY_TYPE} entry to rewrite")
	for entry in selections:
		print(f"  {entry.get('voiceId')}\n    -> {voice_id}")
		entry["voiceId"] = voice_id
	_import(data)
	return 0


def main(argv: list[str]) -> int:
	if len(argv) == 2 and argv[1] == "show":
		return show()
	if len(argv) == 3 and argv[1] == "set":
		return set_voice(argv[2])
	print(__doc__ or "", file=sys.stderr)
	print("usage: voiceover_voice.py show | set <voiceId>", file=sys.stderr)
	return 2


if __name__ == "__main__":
	raise SystemExit(main(sys.argv))
