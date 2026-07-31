# The Go formatting gate.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     uv run poe go-fmt
#
# WHY A SCRIPT AND NOT ONE COMMAND. `gofmt -l` prints the offending file names
# and then exits 0, so a bare `gofmt -l ./...` in a task list is a gate that can
# never fail. The usual shell workaround (`test -z "$(gofmt -l .)"`) needs a
# POSIX shell, which is not what a poe `cmd` task gets on Windows.
#
# WHY IT EXISTS AT ALL. Nothing in this repo checked Go formatting -- not `go
# vet`, not staticcheck, neither of which has an opinion about layout. The
# Python half grew a `ruff format --check` gate after PR #46 added a dozen
# space-indented files to a tab repo; the Go half had the same hole and nobody
# had looked. It was holding two files when this landed, both the same shape:
# a struct field and a map entry added without re-aligning the block around
# them, which is precisely what gofmt is for and precisely what review misses.
#
# A NOTE ON LINE ENDINGS. Run this against a working copy checked out before
# .gitattributes pinned the tree to LF and gofmt reports every file, because a
# CRLF line is not the byte sequence it would write. That is a false alarm about
# the checkout, not a real finding -- and it is loud enough (100+ files) to
# train someone to ignore this gate entirely. `git add --renormalize .` followed
# by a fresh checkout fixes the working copy; CI checks out LF and never sees it.

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVER = ROOT / "server"


def main() -> int:
	try:
		done = subprocess.run(
			["gofmt", "-l", str(SERVER)],
			capture_output=True,
			text=True,
			timeout=180,
		)
	except (OSError, subprocess.TimeoutExpired) as exc:
		print(f"  FAIL  gofmt        could not run gofmt: {exc}")
		return 1
	if done.returncode != 0:
		print(f"  FAIL  gofmt        gofmt exited {done.returncode}: {done.stderr.strip()}")
		return 1

	offenders = [line.strip() for line in done.stdout.splitlines() if line.strip()]
	if not offenders:
		print("  PASS  gofmt        every .go file is gofmt-clean")
		return 0

	print(f"  FAIL  gofmt        {len(offenders)} file(s) are not gofmt-clean")
	for path in offenders:
		print(f"           {Path(path).relative_to(ROOT) if Path(path).is_relative_to(ROOT) else path}")
	print("        -> gofmt -w server")
	# Named explicitly, because the first time this fires on a stale working copy
	# the list is enormous and the cause is not the code.
	if len(offenders) > 20:
		print("        (that many at once usually means a CRLF working copy, not real")
		print("         drift -- see this script's header)")
	return 1


if __name__ == "__main__":
	sys.exit(main())
