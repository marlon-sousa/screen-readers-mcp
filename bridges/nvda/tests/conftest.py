# Headless test harness for the bridge core.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

_TESTS_DIR = Path(__file__).resolve().parent
_ADDON_ROOT = _TESTS_DIR.parent
_GLOBAL_PLUGINS = _ADDON_ROOT / "addon" / "globalPlugins"


def _sync_shared_wire() -> None:
	spec = importlib.util.spec_from_file_location("_sync_shared", _ADDON_ROOT / "sync_shared.py")
	assert spec is not None and spec.loader is not None
	module = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(module)
	module.sync()


_sync_shared_wire()
for _path in (_GLOBAL_PLUGINS, _TESTS_DIR):
	if str(_path) not in sys.path:
		sys.path.insert(0, str(_path))

# Imported after the bootstrap: fakes imports the addon package, which needs globalPlugins on sys.path.
from fakes.clock import FakeClock  # noqa: E402


@pytest.fixture
def clock() -> FakeClock:
	return FakeClock()
