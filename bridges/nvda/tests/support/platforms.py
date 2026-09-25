# Import-time host guards for test modules that cannot even be imported here.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: test scaffolding; call at the top of a module, before the import it guards.
#
# A marker is not enough: it deselects after import, and off Windows the import fails on ctypes.WinDLL.

from __future__ import annotations

import sys

import pytest


def skip_module_unless_windows(reason: str) -> None:
	if sys.platform != "win32":
		pytest.skip(f"Windows only: {reason}", allow_module_level=True)
