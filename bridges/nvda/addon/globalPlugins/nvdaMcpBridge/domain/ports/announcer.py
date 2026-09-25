# nvdaMcpBridge domain -- the Announcer port: the bridge's line to the real synth.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port, the bridge's line to the reader's real synth, which stays loaded in every mode.
# USED BY: the hello handler and the SessionContext.
# IMPLEMENTED BY: adapters/nvda_announcer.py; tests/fakes/announcer.py.
# Nothing may swap or terminate the synth: NVDA and every add-on must keep believing it is the active one.

from __future__ import annotations

import enum
from abc import ABC, abstractmethod


class SilenceNotice(enum.Enum):
	"""The words are the adapter's, in the reader's own locale."""

	WARNING = "warning"
	# The session is still running and still capturing.
	LIFTED = "lifted"
	RESUPPRESSED = "resuppressed"


class Announcer(ABC):
	@abstractmethod
	def current_synth(self) -> str:
		"""For the ``hello`` result."""

	@abstractmethod
	def announce(self, text: str) -> None:
		"""Bypasses silent-mode suppression, which lives in NVDA's ``speak()`` and not in the synth."""

	@abstractmethod
	def silence_notice(self, notice: SilenceNotice) -> None:
		"""Must sound distinct from :meth:`announce`, so the human can tell the bridge from the agent."""
