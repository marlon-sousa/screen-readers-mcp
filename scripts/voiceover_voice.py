#!/usr/bin/env python3
# Read and set VoiceOver's selected voice, by preference (spec 0047, findings 16-17).
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     python3 scripts/voiceover_voice.py show
#     python3 scripts/voiceover_voice.py set com.apple.eloquence.pt-BR.Reed
#
# ROLE: the instrument for the one thing a VoiceOver bridge cannot ask a human to
# do -- point the reader at its capture voice -- and put back afterwards.
#
# WHERE THE VOICE ACTUALLY LIVES, because an evening was spent finding out. NOT in
# VoiceOver's own preferences, and not in its group container: those hold only
# timestamps and runtime state, and VoiceOver's writes during a voice change go
# to /dev/null. The store is the SYSTEM SPEECH domain, one namespace over:
#
#     ~/Library/Preferences/com.apple.SpeakSelection.plist
#         VoiceOverDefaultVoiceSelections = ( "<lang>", Speech.VoiceSelection )
#
# WHY export -> modify -> import, RATHER THAN `defaults write`. An old-style plist
# literal makes every value a STRING. Written that way, `pitch` and `rate` arrive
# as text where reals are expected; VoiceOver silently rejects the record, falls
# back to the system default voice, AND rewrites the key with its own choice -- so
# the evidence of the write is gone before you look, and it presents as "writing
# the preference does nothing". That wrong conclusion is recorded in spec 0047
# finding 2 and was only overturned by finding 17.
#
# The change applies LIVE, in both directions, with no reader restart.

from __future__ import annotations

import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

DOMAIN = "com.apple.SpeakSelection"
KEY = "VoiceOverDefaultVoiceSelections"
#: What the entries we may rewrite call themselves. Anything else is left alone.
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
