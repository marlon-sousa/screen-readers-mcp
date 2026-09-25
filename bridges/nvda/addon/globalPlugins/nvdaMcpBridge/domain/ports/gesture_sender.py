# nvdaMcpBridge domain -- the GestureSender port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port, injecting a keyboard gesture and blocking until NVDA processed it.
# USED BY: PressGestureHandler.
# IMPLEMENTED BY: adapters/nvda_gesture_sender.py; tests/fakes/gesture_sender.py.

from __future__ import annotations

from abc import ABC, abstractmethod


class GestureError(Exception):
	"""A gesture id could not be resolved or emulated; the session survives it."""


class GestureSender(ABC):
	@abstractmethod
	def press(self, gesture_id: str) -> None:
		"""Raises :class:`GestureError` if the id is unknown or NVDA rejects it."""
