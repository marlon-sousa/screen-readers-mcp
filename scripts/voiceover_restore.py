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
#
# ============================================================================
# IT REPORTS THE MACHINE, NOT THE JOURNAL -- 13.32, AND IT DID NOT UNTIL THEN.
# ============================================================================
#
# The three defects below were found by 13.31's own live checklist on 2026-09-03,
# on the maintainer's machine, with his voice left on the capture voice by a
# crashed session -- which is exactly the situation this file exists for, and it
# handled none of it. All three landed in one commit (b558c6e, 13.26) as a botched
# removal of the modifier branch: the half that called `restore_voice` was deleted
# along with the modifier kind, and its `else` survived as `if True:`.
#
#  1. IT PRINTED `now` FROM THE JOURNAL as a statement of present fact. After the
#     voice had been put back by another route it went on saying *"it is now: the
#     screen-readers-mcp capture voice"* -- a log reader presenting log state as
#     machine state, to somebody who is by definition recovering from a crash.
#     Now the machine is read ONCE, at the top, and reported beside the journal.
#  2. `--apply` DID NOT APPLY. `restore_voice` was defined and never called.
#  3. THE INSTRUCTIONS NAMED THE WRONG KEY, offering a PlistBuddy line that set
#     `SCRKeysToUseForVOModifier` -- the VOICEOVER MODIFIER -- to a voice id. That
#     is the setting 13.26 measured must not be written under a running reader:
#     VoiceOver puts a modal question on screen when it changes, which blocks the
#     reader from quitting. Nothing in this repository writes VoiceOver's own
#     preferences, so the whole block is gone rather than corrected.
#
# THE JOURNAL HALF WAS NEVER BROKEN and is untouched: the change was recorded
# correctly, with the right previous value. It was the recovery half that had
# never been exercised against a real open change.
#
# ============================================================================
# A VOICE THAT IS NO LONGER ON THIS MACHINE IS STILL WRITTEN BACK.
# ============================================================================
#
# Spec 0056 §2.5 and §3.4, and it is the same decision the bridge's own teardown
# makes. Writing the recorded identifier is what takes the reader OFF the capture
# voice; refusing would leave a voice that renders nothing selected, and the next
# reader restart would find it unpublished, fall back to the system default AND
# PERSIST THE FALLBACK -- destroying the record of the person's own voice. A
# recovery tool that refused to write would cause the disaster it was cleaning up
# after.
#
# THIS SCRIPT DOES NOT RESOLVE IDENTIFIERS, and that is deliberate. There is no
# `AVSpeechSynthesisVoice.speechVoices()` from stdlib Python; `say -v '?'` prints
# NAMES rather than identifiers and answers about a cache spec 0047 finding 18
# measured lying for an hour. Inventing a resolution here would be inventing a
# second authority that can disagree with the bridge's. So it writes, re-reads,
# and says the one sentence that covers the case honestly.

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

#: How OUR voice is recognised in the preference, and it is a SUFFIX because the
#: system publishes ours as the extension's bundle id followed by the one the
#: audio unit declared -- so the stored string never equals what the unit said
#: (spec 0041, A1). The same constant the bridge matches on, in
#: `Sources/VoiceOverBridgeAdapters/ContainerFileSpeechSource.swift`; if the two
#: ever disagree, this file is the copy and that one is the original.
CAPTURE_VOICE_SUFFIX = "org.screen-readers-mcp.spike.capture"

#: What to tell somebody whose own voice is not on this machine any more. The
#: same path `ReaderCondition.usersVoiceNotAvailable` speaks at the handshake,
#: written here for a person reading a terminal rather than hearing a sentence.
#:
#: IT PROMISES NOTHING IT CANNOT BACK UP: a voice can be advertised on this
#: machine and not installed (board entry 13.15), so "install it" is the action
#: and "the reader will sound right again" is not a claim to make.
MANAGE_VOICES = "System Settings > Accessibility > Spoken Content > System Voice > Manage Voices"

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


def machine_voice() -> str | None:
	"""What the reader is ACTUALLY set to speak with, right now.

	THE FIX FOR 13.32's FIRST DEFECT. This script used to report the journal's own
	`now` field -- what was true when the change was made -- as a statement of
	present fact, so any restore performed by another route made it lie confidently
	to somebody recovering from a crash. Asking the machine is two subprocesses and
	it is the whole difference between a log reader and a repair tool.

	None means the preference could not be read or holds no selection, which is an
	ANSWER and not a failure: a machine where nobody has ever chosen a voice has
	nothing for this script to put back either.
	"""
	try:
		data = _export()
	except (subprocess.CalledProcessError, plistlib.InvalidFileException, OSError):
		return None
	entries = data.get(VOICE_KEY)
	if not isinstance(entries, list):
		return None
	for entry in entries:
		if isinstance(entry, dict) and entry.get("_type") == VOICE_ENTRY_TYPE:
			voice = entry.get("voiceId")
			if isinstance(voice, str) and voice:
				return voice
	return None


def is_capture_voice(voice_id: str | None) -> bool:
	"""Whether the reader is on OUR voice -- the state an open change describes.

	By SUFFIX, never by equality: the system prefixes the extension's bundle id
	onto the identifier the audio unit declared, so the stored string never equals
	our own constant. Same rule as the bridge's, for the same reason.
	"""
	return voice_id is not None and voice_id.endswith(CAPTURE_VOICE_SUFFIX)


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


def is_open_on_the_machine(change: dict[str, object], current: str | None) -> bool:
	"""Whether this change is still TRUE OF THE MACHINE, not merely unclosed.

	THE JOURNAL AND THE MACHINE ARE TWO DIFFERENT QUESTIONS, and conflating them is
	13.32's first defect in its most consequential form. A change has no `restored`
	line whenever the session that made it died -- but somebody may have put the
	setting back since, by hand or with `voiceover_voice.py`, and nothing appends to
	this file except a bridge. So an unclosed entry is a QUESTION and the machine is
	the answer.

	A kind this script cannot read is reported as open, deliberately: "I do not know
	how to check this" must not render as "nothing to see".
	"""
	if change.get("change") != "voice":
		return True
	if current is None:
		# The preference could not be read, so this cannot be ruled out. The safe
		# reading of "I could not look" is "assume it is still open" -- the same rule
		# `process_is_running` applies to a pid it does not own.
		return True
	return is_capture_voice(current)


def describe(change: dict[str, object], live: bool, current: str | None) -> str:
	"""One open change, as the JOURNAL recorded it and as the MACHINE now is.

	`current` is passed in rather than read here, so the reporting stays pure and
	one read serves every change. The two are printed as two separate facts and
	never merged: they can legitimately disagree -- somebody may have put the voice
	back another way -- and that disagreement is the most useful thing this script
	has to say.
	"""
	kind = change.get("change")
	lines = [
		f"* {kind} -- changed by pid {change.get('pid')} at {change.get('at')}"
		+ ("  [THAT SESSION IS STILL RUNNING]" if live else ""),
		f"    where: {change.get('store')}",
		f"    they had: {change.get('was')}",
		f"    the journal recorded it becoming: {change.get('now')}",
	]
	if kind != "voice":
		# A kind a newer build emits and this one cannot repair. REPORTED anyway --
		# silently ignoring it would be a change nobody puts back.
		lines.append(f"    THE MACHINE NOW SAYS: {current or '<could not be read>'}")
		lines.append("    This script does not know how to put this kind back.")
		return "\n".join(lines)

	if current is None:
		lines.append("    THE MACHINE NOW SAYS: <the preference could not be read>")
	elif is_capture_voice(current):
		lines.append(f"    THE MACHINE NOW SAYS: {current}")
		lines.append("    -- which IS the capture voice. This change is still open.")
		lines.append("    HOW TO PUT IT BACK: this script can, with --apply.")
	else:
		lines.append(f"    THE MACHINE NOW SAYS: {current}")
		lines.append("    -- which is NOT the capture voice, so the reader has already been put back,")
		lines.append("    by something other than this script. Nothing here needs applying.")
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

	# READ BEFORE ANYTHING IS PRINTED, AND RE-READ AFTER EVERY WRITE.
	#
	# THE RE-READ WAS ADDED BY THIS ENTRY'S OWN LIVE RUN, and it is 13.32's first
	# defect committed a second time by the fix for it. This was written to read
	# ONCE, on the reasoning that every change should be reported against one
	# consistent snapshot -- which is a good rule for a report and a wrong one here,
	# because THIS LOOP MUTATES THE MACHINE IT IS DESCRIBING. Measured 2026-09-03
	# with two open changes in the journal: the first was applied, and the second was
	# then described against the pre-write snapshot, printing *"which IS the capture
	# voice. This change is still open."* about a reader that had just been put back
	# -- and writing it again. Harmless that time, because both entries recorded the
	# same previous voice; two entries recording DIFFERENT voices would have had the
	# second overwrite the first's repair.
	#
	# So `current` means "what the machine says NOW", it is refreshed wherever this
	# script changes that, and the rule is the one the whole entry is about: never
	# report a reading taken before the thing you did.
	current = machine_voice()

	# AND THE HEADLINE COUNTS THE MACHINE TOO, which is the same defect one level
	# up. "1 setting(s) still changed" over a machine that has already been put back
	# is the first thing somebody reads, and it was the sentence that sent 13.31's
	# checklist looking for a problem that no longer existed.
	open_now = [c for c in changes if is_open_on_the_machine(c, current)]
	if not open_now:
		print(
			f"{args.journal}: {len(changes)} change(s) with no `restored` line, and NOTHING IS\n"
			"STILL CHANGED ON THIS MACHINE. Each one below was put back by something other\n"
			"than this script, which is why the journal never closed it.\n"
		)
	else:
		print(f"{args.journal}: {len(open_now)} setting(s) still changed on this machine.\n")
	acted = False
	for change in changes:
		live = process_is_running(change.get("pid"))
		print(describe(change, live, current))
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
		if not is_capture_voice(current):
			# NOT AN ERROR, AND NOT SILENCE EITHER. Somebody has already put the voice
			# back; writing over their choice would be this script undoing a repair it
			# was asked to perform.
			print(
				"  SKIPPED: the reader is not on the capture voice any more, so this change\n"
				"  has already been put back. Nothing was written.\n"
			)
			continue
		# THE CALL THIS SCRIPT WAS MISSING. It was defined and never reached, so
		# `--apply` printed instructions and changed nothing -- 13.32's second defect.
		if restore_voice(was):
			acted = True
			# AND THE SNAPSHOT IS NOW STALE. See the read above: the next change in
			# this loop must be described against the machine as it is after this
			# write, not as it was before it.
			current = machine_voice()

	if args.apply and acted:
		# RE-READ, so the closing line reports what is TRUE rather than what was
		# attempted. This is the same rule as the write's own confirmation in the
		# bridge: a record VoiceOver rejects is rewritten with its own choice, so a
		# write that failed looks exactly like one that was never made.
		now = machine_voice()
		print(f"Done. The reader is now set to: {now or '<the preference could not be read>'}")
		print("The change applies live; nothing needs restarting for the voice.")
		if now is not None and not is_capture_voice(now):
			# THE ONE SENTENCE THAT COVERS THE CASE THIS SCRIPT CANNOT TEST FOR. It
			# does not resolve identifiers -- see the header -- so it cannot say
			# whether that voice is still installed, only what it wrote.
			print()
			print(
				"If the reader still does not sound like your own voice, that voice is no\n"
				f"longer installed on this machine. Install it again, or choose another:\n"
				f"  {MANAGE_VOICES}"
			)
	elif args.apply:
		print("Nothing needed putting back. Every open change above says why.")
	else:
		print("Nothing was changed. Run again with --apply to put back what can be put back.")
	return 0


if __name__ == "__main__":
	raise SystemExit(main(sys.argv))
