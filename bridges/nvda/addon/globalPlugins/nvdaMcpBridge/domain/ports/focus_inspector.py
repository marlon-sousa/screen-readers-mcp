# nvdaMcpBridge domain -- the FocusInspector port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port, a structured snapshot of what NVDA is focused on.
# USED BY: the GetFocusInfoHandler.
# IMPLEMENTED BY: adapters/nvda_focus_inspector.py; tests/fakes/focus_inspector.py.

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass(frozen=True)
class FocusInfo:
	"""Role and states are stable enum names, never localized display strings."""

	name: str
	role: str
	states: list[str]
	value: str | None
	app_module: str | None


class FocusInspector(ABC):
	@abstractmethod
	def focus_info(self) -> FocusInfo:
		"""A null focus yields a ``FocusInfo`` with empty fields rather than raising."""
