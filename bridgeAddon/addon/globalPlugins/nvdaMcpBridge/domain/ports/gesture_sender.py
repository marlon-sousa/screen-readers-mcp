# nvdaMcpBridge domain -- the GestureSender port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from abc import ABC, abstractmethod


class GestureSender(ABC):
	"""Emulates an NVDA keyboard gesture, blocking until it is processed.

	``gesture_id`` is an NVDA identifier such as ``"NVDA+f7"`` or
	``"control+shift+downArrow"``. Raises :class:`ValueError` for an
	unparseable identifier so the bridge can report a clear wire error.
	"""

	@abstractmethod
	def send(self, gesture_id: str) -> None: ...
