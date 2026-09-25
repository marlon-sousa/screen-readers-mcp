#!/usr/bin/env python3
# Copy the canonical shared wire module into the addon package.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
SOURCE = _HERE.parent.parent / "shared" / "screenreader_wire" / "protocol.py"
DEST = _HERE / "addon" / "globalPlugins" / "nvdaMcpBridge" / "protocol.py"

_HEADER = (
	"# AUTO-GENERATED COPY -- do not edit.\n"
	"# Source of truth: shared/screenreader_wire/protocol.py (run bridges/nvda/sync_shared.py).\n"
)


def sync() -> Path:
	if not SOURCE.is_file():
		raise SystemExit(f"shared wire module not found: {SOURCE}")
	DEST.parent.mkdir(parents=True, exist_ok=True)
	DEST.write_text(_HEADER + SOURCE.read_text(encoding="utf-8"), encoding="utf-8")
	return DEST


if __name__ == "__main__":
	dest = sync()
	sys.stdout.write(f"synced {SOURCE} -> {dest}\n")
