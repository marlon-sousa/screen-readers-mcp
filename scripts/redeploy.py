# Redeploy the MCP server binary: kill every running copy, then rebuild.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# WHY THIS EXISTS: rebuilding the server fails while the binary is running --
# Windows locks a loaded image against being overwritten --
# and with stdio MCP there is no single server to ask nicely. Each CLIENT spawns
# its OWN process, so a session with two agents attached has two copies of the
# same exe holding the same file, and no shared endpoint to shut down. An HTTP
# transport would have one; stdio does not. Killing by image path is the only
# thing that reaches all of them.
#
# WHY KILLING IS SAFE, which is not obvious for a tool that drives a screen
# reader: the bridge treats a dropped connection as teardown, and teardown
# unregisters the speech filter. So a killed server leaves the tester HEARING,
# not mute -- the invariant spec 0016 is arranged around, asserted headlessly by
# test_a_client_that_vanishes_with_a_prompt_open_leaves_speech_on and live by
# test_a_session_that_dies_with_a_window_open_recovers. A killed server also
# ends any silent-mode session, so speech comes back within one read timeout.
#
# The cost is real and deliberate (Marlon's call): EVERY agent's connection to
# this binary dies, not just the one asking. That is why the run reports each pid
# it killed, and why --dry-run exists to check the targeting first.
#
# ON POSIX the file-locking half of the argument does not apply -- a running
# executable can be replaced, and `go build` writes a new file and renames it
# anyway -- but the KILLING half still does, and it is the half that matters:
# clients respawn their own servers, so a copy left running is a copy still
# serving the code this task exists to replace.

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

# The doctor owns both the binary's path and the definition of "stale".
# Importing them rather than restating them is what keeps `poe dev` and
# `poe doctor` from ever disagreeing about whether this binary is current -- a
# disagreement whose symptom would be dev passing and the doctor failing on the
# same unchanged tree. scripts/ is sys.path[0] when either file is run directly,
# so this is a plain sibling import needing no package.
from build_server import build
from doctor import BINARY, stale_server_binary
from platforms import HOST, Host

ROOT = Path(__file__).resolve().parents[1]


def _run(args: list[str], cwd: Path | None = None) -> tuple[int, str]:
	try:
		done = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=300)
	except (OSError, subprocess.TimeoutExpired) as exc:
		return 1, str(exc)
	return done.returncode, (done.stdout + done.stderr).strip()


def running_copies() -> list[tuple[int, str]]:
	"""Every process running THIS repo's server binary, as (pid, path).

	Matched on the executable's PATH, not merely its name: another checkout of
	this project, or an installed copy elsewhere, is somebody else's server and
	must not be killed because it happens to share a filename.
	"""
	return _windows_copies() if HOST is Host.WINDOWS else _posix_copies()


def _windows_copies() -> list[tuple[int, str]]:
	"""CIM rather than the deprecated wmic."""
	script = (
		f"Get-CimInstance Win32_Process -Filter \"Name='{BINARY.name}'\" | "
		'ForEach-Object { "$($_.ProcessId)|$($_.ExecutablePath)" }'
	)
	code, out = _run(["powershell", "-NoProfile", "-Command", script])
	if code != 0:
		print(f"  could not enumerate processes: {out}", file=sys.stderr)
		return []
	wanted = str(BINARY).casefold()
	found: list[tuple[int, str]] = []
	for line in out.splitlines():
		pid, _, path = line.partition("|")
		if not pid.strip().isdigit():
			continue
		if path.strip().casefold() == wanted:
			found.append((int(pid), path.strip()))
	return found


def _executable_of(pid: int, reported: str) -> str:
	"""The real path behind a pid, as well as this host can answer it.

	Linux answers exactly, through /proc/<pid>/exe. macOS has no /proc, but its
	`ps -o comm` already prints the full path, so the reported value IS the
	answer there. The weaker case -- a `ps` that reports only a basename -- falls
	back to that basename and will therefore not match BINARY's full path, so it
	kills nothing rather than killing the wrong thing.
	"""
	try:
		return os.readlink(f"/proc/{pid}/exe")
	except OSError:
		return reported


def _posix_copies() -> list[tuple[int, str]]:
	"""`ps` across every user's processes, then narrowed to this exact file.

	Matched by resolved path, like the Windows branch. It is a weaker match than
	Win32's ExecutablePath -- a process that rewrote its own argv or exec'd
	through a symlink could evade it -- and that is accepted rather than papered
	over: this is a dev tool killing dev servers.
	"""
	code, out = _run(["ps", "-Ao", "pid=,comm="])
	if code != 0:
		print(f"  could not enumerate processes: {out}", file=sys.stderr)
		return []
	found: list[tuple[int, str]] = []
	for line in out.splitlines():
		pid_text, _, reported = line.strip().partition(" ")
		if not pid_text.isdigit():
			continue
		reported = reported.strip()
		if Path(reported).name != BINARY.name:
			continue
		path = _executable_of(int(pid_text), reported)
		try:
			if Path(path).resolve() == BINARY.resolve():
				found.append((int(pid_text), path))
		except OSError:
			continue
	return found


def _posix_kill(pid: int, grace: float = 5.0) -> str:
	"""SIGTERM, then SIGKILL if it is still there.

	SIGTERM first because the server's exit is what the bridge reads as teardown,
	and teardown is what unregisters the speech filter -- the invariant this whole
	tool is arranged around. SIGKILL only after the grace period, because a
	server that will not leave is worse than an abrupt one: the bridge treats a
	dropped connection as teardown either way.
	"""
	try:
		os.kill(pid, signal.SIGTERM)
	except OSError as exc:
		return f"could not kill ({exc})"
	deadline = time.monotonic() + grace
	while time.monotonic() < deadline:
		try:
			os.kill(pid, 0)
		except OSError:
			return "killed"
		time.sleep(0.1)
	try:
		os.kill(pid, signal.SIGKILL)
	except OSError as exc:
		return f"could not kill ({exc})"
	return "killed (SIGKILL, it ignored SIGTERM)"


def _is_replaceable() -> bool:
	"""Whether the binary can be overwritten right now.

	Opening a loaded image for writing raises PermissionError on Windows, which
	makes this a direct test of the thing we actually care about -- rather than
	inferring it from a process list that may be a moment out of date, since a
	handle is released slightly after the process disappears.

	On POSIX it is essentially always true, and deliberately still asked: the
	answer is the same shape, the wait loop below simply returns immediately, and
	there is no second code path to keep honest.
	"""
	if not BINARY.exists():
		return True
	try:
		with open(BINARY, "r+b"):
			return True
	except PermissionError:
		return False
	except OSError:
		return False


def kill_all(dry_run: bool) -> int:
	copies = running_copies()
	if not copies:
		print("  no running copies of the server -- nothing to kill")
		return 0
	for pid, path in copies:
		if dry_run:
			print(f"  WOULD kill pid {pid} ({path})")
			continue
		if HOST is Host.WINDOWS:
			code, out = _run(["taskkill", "/F", "/PID", str(pid)])
			state = "killed" if code == 0 else f"could not kill ({out})"
		else:
			state = _posix_kill(pid)
		print(f"  pid {pid}: {state}")
	return len(copies)


def wait_until_replaceable(timeout: float = 10.0) -> bool:
	"""Wait for the file handle to be released, not merely for the pid to go."""
	deadline = time.monotonic() + timeout
	while time.monotonic() < deadline:
		if _is_replaceable():
			return True
		time.sleep(0.2)
	return _is_replaceable()


def remove_binary(timeout: float = 10.0) -> bool:
	"""Delete the binary, so a respawn cannot resurrect the OLD code.

	Killing alone is not enough: the image stays on disk, and the clients demonstrably
	respawn their servers on their own, so between the kill and the end of the build
	somebody can load exactly the code this task exists to replace. With the file gone
	a respawn simply fails to start -- noisier for that client, and the point: it
	reports a missing binary instead of quietly serving stale behaviour.

	Retried because deletion, like overwriting, is refused while any process still has
	the image loaded.
	"""
	deadline = time.monotonic() + timeout
	while time.monotonic() < deadline:
		if not BINARY.exists():
			return True
		try:
			BINARY.unlink()
			print("  deleted the old binary, so nothing can respawn onto it")
			return True
		except PermissionError:
			time.sleep(0.2)
		except OSError as exc:
			print(f"  could not delete the binary: {exc}", file=sys.stderr)
			return False
	return not BINARY.exists()


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument(
		"--dry-run",
		action="store_true",
		help="report which processes would be killed, and build nothing",
	)
	parser.add_argument(
		"--if-stale",
		action="store_true",
		help="do nothing when the binary is already newer than every server/*.go",
	)
	args = parser.parse_args()

	# What `poe dev` calls. The whole point is that it is a NO-OP in the common
	# case: no kill, no build, no other agent's session dropped -- because the
	# expensive side effects are only warranted when there is actually new Go code
	# to deploy. When there is, dev deploys it up front rather than doing a
	# minute's work and then failing the doctor on it, which cost two full runs
	# every time and is the reason this flag exists.
	if args.if_stale and not args.dry_run:
		reason = stale_server_binary()
		if reason is None:
			print("Server binary is current -- nothing to redeploy.")
			return 0
		print(f"Server binary is stale ({reason}).")

	print("Redeploying the MCP server binary.")

	if args.dry_run:
		killed = kill_all(dry_run=True)
		print(f"\nDry run: {killed} process(es) would be killed, nothing was built.")
		return 0

	# Retried, because a client can respawn its server between the kill and the
	# build and lock the file again -- observed: the pids seen at the start of a
	# session were not the ones seen an hour later, so respawning is what clients
	# actually do rather than a theoretical worry. A copy that respawns AFTER the
	# build is harmless; it loads the new binary. Only the window in between
	# matters, so the fix is to close it by trying again rather than to fail.
	attempts = 3
	for attempt in range(1, attempts + 1):
		if attempt > 1:
			print(f"  the binary was locked again -- retrying ({attempt} of {attempts})")
		killed = kill_all(dry_run=False)
		if killed and not wait_until_replaceable():
			continue
		# Delete before building, not merely overwrite: while the old image is on
		# disk a respawning client can load it, and the whole point is that nobody
		# ends up on the code being replaced.
		if not remove_binary():
			continue
		if build():
			break
		if not _is_replaceable():
			continue
		print("\nFAILED: the build itself failed; the old binary is still in place.", file=sys.stderr)
		return 1
	else:
		print(
			"\nFAILED: the binary stayed locked across every attempt. A client is "
			"respawning it faster than it can be replaced -- close one, or stop the "
			"agents attached to it, and run this again.",
			file=sys.stderr,
		)
		return 1

	print(
		"\nDone. Every server process was killed, including other agents', and the old "
		"binary was deleted before the new one was written -- so nothing can still be "
		"answering from the code you just replaced.\n"
		"\n"
		"A client picks the NEW BINARY up by itself on its next tool call, and since "
		"spec 0022 (option (c)) the tool LIST it picks up is still a correct one: the "
		"list is a CONSTANT, so the cached copy this kill stranded still names every "
		"tool this build has.\n"
		"\n"
		"That is board entry 11.6, and only that. Killing the server still drops it out "
		"of the client's managed lifecycle, and the client still silently respawns it "
		"without re-running capability discovery -- but there is no longer anything to "
		"discover, because nothing about the surface changes when a SESSION opens.\n"
		"\n"
		"What a constant list cannot do is stay correct across a REBUILD, and this "
		"script is a rebuild. The names do not change; the SCHEMAS inside them can, and "
		"that is board entry 11.26 rather than 11.6 wearing the same first symptom.\n"
		"\n"
		"RECONNECT IF THE SURFACE CHANGED IN THIS BUILD -- a tool added or removed, OR "
		"A TOOL'S PARAMETERS OR RESULT CHANGED:\n"
		"\n"
		"    /mcp reconnect screen-reader-testing\n"
		"\n"
		"Then the cached list is genuinely out of date -- not because a session began, "
		"but because the SERVER's own surface is not what it was when the client "
		"listed. THE CACHE INCLUDES EACH TOOL'S SCHEMA, not just the names: a parameter "
		"this build added is one the client will not send correctly until it lists "
		"again, and it fails TYPED -- an unmarshalling error about JSON and Go structs, "
		"naming nothing that would lead you back here. That is board entry 11.26, and "
		"this line used to say `only if you added or removed a tool`, which is the "
		"advice that cost a session on 2026-08-21.\n"
		"\n"
		"Name the server: a bare `/mcp reconnect` does not take. Only the human at the "
		"keyboard can run it -- it is client UI, not anything an agent can reach. An "
		"AGENT that suspects it is holding a stale schema can read "
		"`screenreader://tools` instead: a resource is served live and never cached, so "
		"it describes the build that is actually running.\n"
		"scripts/live_test.py is immune: its own MCP client, its own server process."
	)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
