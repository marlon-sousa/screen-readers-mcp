# The Go formatting gate.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     uv run poe go-fmt
#
# `gofmt -l` exits 0 even when it lists files, so this script turns its output into the exit code.
# A CRLF working copy makes gofmt list every file; renormalise and check out again to fix it.

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
	if len(offenders) > 20:
		print("        (that many at once usually means a CRLF working copy, not real")
		print("         drift -- see this script's header)")
	return 1


if __name__ == "__main__":
	sys.exit(main())
