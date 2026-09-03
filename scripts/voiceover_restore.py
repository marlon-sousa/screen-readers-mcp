#!/usr/bin/env python3
# Read the bridge's change journal and put back what a session did not.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     python3 scripts/voiceover_restore.py            # what is still changed
#     python3 scripts/voiceover_restore.py --apply    # put it back
#
# ROLE: the READER of `~/Library/Logs/screen-readers-mcp/reader-changes.jsonl`,
# which the bridge writes and never reads. Board entry 13.26, spec 0053 §3.10.
#
# ============================================================================
# WHY THIS EXISTS, AND IT IS NOT A HYPOTHETICAL.
# ============================================================================
#
# From the 2026-09-02 field report (`docs/feedback/2026-09-02-acter-run.md`): a
# handshake failed at `captureProof` and left the capture voice SELECTED -- a
# voice that renders nothing, on the machine of the person who depends on it. No
# MCP call could say what setup had changed. Recovery meant reading this
# repository's Swift source to learn where the selection lives and that it must be
# export-modify-imported rather than written with `defaults`; the hand edit that
# followed destroyed the user's pitch, rate and volume and dropped them from their
# premium Luciana voice to the compact one, and VoiceOver rebuilt the selection on
# its next start with those values gone.
#
# Marlon's answer, the same day: "If all changed files are recorded in one file,
# we have our perfect snapshot."
#
# ============================================================================
# AN OPEN CHANGE IS THE PRODUCT.
# ============================================================================
#
# Every line is one setting a session changed, or put back. A `changed` with no
# matching `restored` is exactly what a crashed session left behind -- and a
# crashed session is the only reason the file exists, because an orderly teardown
# closes everything it opened. Everything else in the file is history.
#
# IT IS SAFE TO RUN BLIND, which is the field report's actual ask. With no
# arguments it changes nothing and prints what is open. `--apply` restores only
# what CAN be restored by writing a setting, and refuses to touch anything else.
#
# ============================================================================
# A LIVE SESSION'S CHANGE IS NOT AN ABANDONED ONE.
# ============================================================================
#
# Each line carries the `pid` that wrote it. A change whose process is STILL
# RUNNING belongs to a session that has not finished, and restoring it would be
# reaching into a live run and taking the capture voice away mid-test. So those
# are reported separately and never applied unless `--force` says so.

from __future__ import annotations

import argparse
import json
import os
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

JOURNAL = Path.home() / "Library/Logs/screen-readers-mcp/reader-changes.jsonl"

#: The system speech domain -- NOT VoiceOver's own, which holds no voice at all.
#: Spec 0047 findings 10 and 16; `scripts/voiceover_voice.py` is the same
#: mechanism as a tool, and this file must not disagree with it.
VOICE_DOMAIN = "com.apple.SpeakSelection"
VOICE_KEY = "VoiceOverDefaultVoiceSelections"
VOICE_ENTRY_TYPE = "Speech.VoiceSelection"

#: What this script will put back by writing a setting.
#:
#: ONE KIND TODAY. 13.26 briefly journalled the VoiceOver modifier too, for a
#: handshake that borrowed Control-Option on a Caps-Lock machine; the live run
#: found that writing that preference under a running reader makes VoiceOver put a
#: modal question on screen, and the borrow came out. If a modifier kind returns it
#: returns with a design that does not write the person's preferences at all.
#:
#: AN UNKNOWN KIND IS STILL REPORTED, just not applied -- see `main`. A journal
#: written by a newer build than this script must not be silently ignored.
REPAIRABLE = {"voice"}


def read_journal(path: Path) -> list[dict[str, object]]:
	"""Every entry, in order. A line that does not parse is REPORTED, not skipped
	silently: this file's whole job is to be trustworthy after a crash, and a
	quietly dropped line is a change nobody puts back."""
	if not path.exists():
		return []
	entries: list[dict[str, object]] = []
	for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
		line = line.strip()
		if not line:
			continue
		try:
			entry = json.loads(line)
		except json.JSONDecodeError as error:
			print(f"{path}:{number}: could not be read as JSON ({error})", file=sys.stderr)
			continue
		if isinstance(entry, dict):
			entries.append(entry)
	return entries


def open_changes(entries: list[dict[str, object]]) -> list[dict[str, object]]:
	"""The changes with no matching restore, newest first.

	Paired on (pid, change), because two sessions may each have touched the voice
	and one of them may have tidied up after itself. Pairing on the kind alone
	would let a clean session close a crashed one's entry, which is the one
	mistake this function must not make.
	"""
	pending: dict[tuple[object, object], dict[str, object]] = {}
	for entry in entries:
		key = (entry.get("pid"), entry.get("change"))
		if entry.get("restored") is True:
			pending.pop(key, None)
		else:
			pending[key] = entry
	return list(reversed(list(pending.values())))


def process_is_running(pid: object) -> bool:
	"""Whether the session that wrote a change is still going.

	`os.kill(pid, 0)` asks the kernel without sending anything. A pid we do not
	own answers `PermissionError`, which still means it EXISTS -- and the safe
	reading of "it exists" here is "leave it alone".
	"""
	if not isinstance(pid, int):
		return False
	try:
		os.kill(pid, 0)
	except ProcessLookupError:
		return False
	except PermissionError:
		return True
	return True


# -- the one thing this script can actually put back --------------------------


def _export() -> dict[str, object]:
	path = Path(tempfile.mktemp(suffix=".plist"))
	subprocess.run(["defaults", "export", VOICE_DOMAIN, str(path)], check=True)
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
		subprocess.run(["defaults", "import", VOICE_DOMAIN, str(path)], check=True)
	finally:
		path.unlink(missing_ok=True)


def restore_voice(voice_id: str) -> bool:
	"""Point VoiceOver back at the voice the person chose.

	EXPORT -> MODIFY -> IMPORT, never `defaults write`, and the reason is the
	whole of spec 0047 finding 2: an old-style plist literal makes every value a
	STRING, so `pitch` and `rate` arrive as text where reals are expected,
	VoiceOver silently rejects the record, falls back to the system default AND
	REWRITES THE KEY with its own choice. The evidence of the write is gone before
	you look. `plistlib` round-trips the types, which is why this parses rather
	than formats -- and it is exactly what the hand recovery in the field report
	did not do.
	"""
	data = _export()
	entries = data.get(VOICE_KEY)
	if not isinstance(entries, list):
		print(f"  {VOICE_DOMAIN} has no {VOICE_KEY}: nothing to rewrite", file=sys.stderr)
		return False
	selections = [e for e in entries if isinstance(e, dict) and e.get("_type") == VOICE_ENTRY_TYPE]
	if not selections:
		print(f"  no {VOICE_ENTRY_TYPE} record to rewrite", file=sys.stderr)
		return False
	for entry in selections:
		print(f"  voice: {entry.get('voiceId')}\n      -> {voice_id}")
		entry["voiceId"] = voice_id
	_import(data)
	return True


# -- reporting ----------------------------------------------------------------


def describe(change: dict[str, object], live: bool) -> str:
	kind = change.get("change")
	lines = [
		f"* {kind} -- changed by pid {change.get('pid')} at {change.get('at')}"
		+ ("  [THAT SESSION IS STILL RUNNING]" if live else ""),
		f"    where: {change.get('store')}",
		f"    they had: {change.get('was')}",
		f"    it is now: {change.get('now')}",
	]
	if kind == "voice":
		lines.append("    HOW TO PUT IT BACK: this script can, with --apply.")
	return "\n".join(lines)


def main(argv: list[str]) -> int:
	parser = argparse.ArgumentParser(
		description="Report and repair what a screen-readers-mcp session left changed."
	)
	parser.add_argument(
		"--apply", action="store_true", help="put back what can be put back (default: report only)"
	)
	parser.add_argument(
		"--force",
		action="store_true",
		help="also act on changes whose session is still running (dangerous: it reaches into a live run)",
	)
	parser.add_argument("--journal", type=Path, default=JOURNAL, help=f"default: {JOURNAL}")
	args = parser.parse_args(argv[1:])

	entries = read_journal(args.journal)
	if not entries:
		print(f"{args.journal}: no journal, or nothing in it. Nothing has been left changed.")
		return 0

	changes = open_changes(entries)
	if not changes:
		print(f"{args.journal}: {len(entries)} entries, and NOTHING IS LEFT OPEN.")
		print("Every session that changed something on this machine put it back.")
		return 0

	print(f"{args.journal}: {len(changes)} setting(s) still changed.\n")
	acted = False
	for change in changes:
		live = process_is_running(change.get("pid"))
		print(describe(change, live))
		print()
		if not args.apply:
			continue
		if change.get("change") not in REPAIRABLE:
			continue
		if live and not args.force:
			print("  SKIPPED: that session is still running. Finish it, or pass --force.\n")
			continue
		was = change.get("was")
		if not isinstance(was, str) or not was:
			print(
				"  SKIPPED: the journal does not record what they had, so there is nothing\n"
				"  to put back. Choose a voice by hand in VoiceOver Utility.\n"
			)
			continue
		if True:
			# The modifier preference. Rare -- it means a session could not put it
			# back itself -- and it is VoiceOver's own group container, which
			# `defaults` cannot reach (measured 2026-09-02), so the honest answer is
			# to name the file and the value rather than to half-write it.
			print(
				"  This one is in VoiceOver's own group container, which `defaults` cannot\n"
				"  reach. Set it in VoiceOver Utility > Commands, which is the supported way,\n"
				f"  or with the reader stopped:\n"
				f"    /usr/libexec/PlistBuddy -c 'Set :SCRKeysToUseForVOModifier {was}' \\\n"
				"      ~/Library/Group\\ Containers/group.com.apple.VoiceOver/Library/Preferences/"
				"com.apple.VoiceOver4/default.plist\n"
			)

	if args.apply and acted:
		print("Done. The change applies live; nothing needs restarting for the voice.")
	elif not args.apply:
		print("Nothing was changed. Run again with --apply to put back what can be put back.")
	return 0


if __name__ == "__main__":
	raise SystemExit(main(sys.argv))
