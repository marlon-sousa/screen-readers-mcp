# nvdaMcpBridge -- NVDA MCP Bridge addon package.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# GlobalPlugin is resolved lazily so that importing this package never imports NVDA.

from __future__ import annotations

from typing import Any


def __getattr__(name: str) -> Any:
	if name == "GlobalPlugin":
		from .plugin import GlobalPlugin

		return GlobalPlugin
	raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
