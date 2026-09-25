# nvdaMcpBridge domain -- the StateSetter port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port; arrives at a mode the reader already gives its user a command for, idempotently.
# USED BY: the SetStateHandler.
# IMPLEMENTED BY: adapters/nvda_state_setter.py and tests/fakes/state_setter.py.
# The compare happens inside the adapter on the reader's thread; comparing in the handler reopens the race.

from __future__ import annotations

from abc import ABC, abstractmethod


class StateSetError(Exception):
	"""A mode that cannot be reached; the message names the specific obstacle."""


class StateSetter(ABC):
	@abstractmethod
	def set_browse_mode(self, target: str) -> bool:
		"""Return whether this call changed the mode; when already there, do nothing audible at all."""
