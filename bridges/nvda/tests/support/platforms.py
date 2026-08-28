# Import-time host guards for test modules that cannot even be IMPORTED here.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: test scaffolding, not a port double -- hence support/ and not fakes/
# (root AGENTS.md, "Testing"). Called at the TOP of a module, before the import
# it is guarding.
#
# WHY A MARKER IS NOT ENOUGH, and this is the whole reason the file exists: a
# marker deselects a test AFTER its module has been imported. The two named-pipe
# modules import an adapter whose module body calls `ctypes.WinDLL`, so on any
# non-Windows host collection dies with an AttributeError before selection ever
# happens -- `pytestmark = pytest.mark.live_nvda` and `-m 'not live_nvda'`
# notwithstanding. The guard has to run at import time or it is not a guard.
#
# WHY A SKIP AND NOT `collect_ignore`: a conftest that ignores the file makes the
# tests DISAPPEAR -- the suite count drops and nothing says a transport went
# untested on this machine. A module-level skip reports as a skip, and puts the
# reason at the site instead of in a list somewhere else.
#
# It deliberately does NOT consult the bridge registry in scripts/bridges.py.
# These modules are Windows-only because of the TRANSPORT -- a Win32 named pipe
# -- and not because of the reader, and a guard that read the reader's
# declaration would state a relationship that does not exist. See spec 0042.

from __future__ import annotations

import sys

import pytest


def skip_module_unless_windows(reason: str) -> None:
	"""Skip the whole calling module, with its reason, unless this is Windows."""
	if sys.platform != "win32":
		pytest.skip(f"Windows only: {reason}", allow_module_level=True)
