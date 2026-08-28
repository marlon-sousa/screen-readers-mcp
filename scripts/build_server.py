# Build the MCP server binary, under the name this host gives an executable.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     uv run poe build-server
#
# ROLE: the one place the server's build command lives. It became a script when
# the output name stopped being a literal: `screenreader-mcp.exe` on Windows and
# `screenreader-mcp` elsewhere cannot be spelled in a poe `cmd` string, and two
# places computing it is two places to get it wrong. redeploy.py imports `build`
# from here rather than restating the command, which is what keeps `poe
# build-server` and `poe redeploy` from ever producing different binaries.
#
# The server is built on EVERY host with no guard -- that is the requirement, not
# an observation (spec 0042, decision 1). Nothing in this file asks which host it
# is on except to name the output.

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from platforms import SERVER_BINARY_NAME

ROOT = Path(__file__).resolve().parent.parent


def build() -> bool:
	"""Compile the server. Prints go's own output; returns whether it worked."""
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
