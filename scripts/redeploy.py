# Redeploy the MCP server binary: kill every running copy, then rebuild.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# Every MCP client spawns its own copy over stdio, and Windows refuses to overwrite a loaded image,
# so every copy of this checkout's binary is killed, other agents' included.
# Killing is safe for the tester: the bridge treats a dropped connection as teardown, which
# unregisters the speech filter.

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

# The doctor owns the binary's path and the definition of stale, so `poe dev` and `poe doctor` agree.
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
	"""Matched on the full path, so another checkout's server is never killed."""
	return _windows_copies() if HOST is Host.WINDOWS else _posix_copies()


def _windows_copies() -> list[tuple[int, str]]:
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
	"""A `ps` that reports only a basename never matches BINARY, so it kills nothing."""
	try:
		return os.readlink(f"/proc/{pid}/exe")
	except OSError:
		return reported


def _posix_copies() -> list[tuple[int, str]]:
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
	"""Opening a loaded image for writing raises PermissionError on Windows."""
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
	"""A handle is released slightly after its process disappears."""
	deadline = time.monotonic() + timeout
	while time.monotonic() < deadline:
		if _is_replaceable():
			return True
		time.sleep(0.2)
	return _is_replaceable()


def remove_binary(timeout: float = 10.0) -> bool:
	"""Deleted so a client that respawns before the build fails to start instead of serving old code."""
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

	# A client can respawn its server and lock the file again between the kill and the build.
	attempts = 3
	for attempt in range(1, attempts + 1):
		if attempt > 1:
			print(f"  the binary was locked again -- retrying ({attempt} of {attempts})")
		killed = kill_all(dry_run=False)
		if killed and not wait_until_replaceable():
			continue
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
