# Build the MCP server binary, under the name this host gives an executable.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     uv run poe build-server
#
# ROLE: the one place the server's build command lives.
# USED BY: `poe build-server`, and redeploy.py, which imports `build`.

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from platforms import SERVER_BINARY_NAME

ROOT = Path(__file__).resolve().parent.parent


def build() -> bool:
	print(f"  building server/{SERVER_BINARY_NAME}")
	try:
		done = subprocess.run(
			["go", "-C", "server", "build", "-o", SERVER_BINARY_NAME, "./cmd/screenreader-mcp"],
			cwd=ROOT,
			capture_output=True,
			text=True,
			timeout=300,
		)
	except (OSError, subprocess.TimeoutExpired) as exc:
		print(f"  {exc}", file=sys.stderr)
		return False
	out = (done.stdout + done.stderr).strip()
	if out:
		print("  " + out.replace("\n", "\n  "))
	return done.returncode == 0


def main() -> int:
	return 0 if build() else 1


if __name__ == "__main__":
	sys.exit(main())
