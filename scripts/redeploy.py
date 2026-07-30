# Redeploy the MCP server binary: kill every running copy, then rebuild.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# WHY THIS EXISTS: `go build -o server/screenreader-mcp.exe` fails while the
# binary is running -- Windows locks a loaded image against being overwritten --
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

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "server" / "screenreader-mcp.exe"


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
	must not be killed because it happens to share a filename. CIM rather than
	the deprecated wmic.
	"""
	script = (
		"Get-CimInstance Win32_Process -Filter \"Name='screenreader-mcp.exe'\" | "
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


def _is_replaceable() -> bool:
	"""Whether the binary can be overwritten right now.

	Opening a loaded image for writing raises PermissionError on Windows, which
	makes this a direct test of the thing we actually care about -- rather than
	inferring it from a process list that may be a moment out of date, since a
	handle is released slightly after the process disappears.
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
		code, out = _run(["taskkill", "/F", "/PID", str(pid)])
		state = "killed" if code == 0 else f"could not kill ({out})"
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


def build() -> bool:
	print("  building server/screenreader-mcp.exe")
	code, out = _run(
		["go", "-C", "server", "build", "-o", "screenreader-mcp.exe", "./cmd/screenreader-mcp"],
		cwd=ROOT,
	)
	if out:
		print("  " + out.replace("\n", "\n  "))
	return code == 0


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument(
		"--dry-run",
		action="store_true",
		help="report which processes would be killed, and build nothing",
	)
	args = parser.parse_args()

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
		"Clients that spawn their server lazily pick the new binary up on their next "
		"tool call (observed in Claude Code: no manual step). A client that holds one "
		"process for a whole session needs its MCP connection restarted."
	)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
