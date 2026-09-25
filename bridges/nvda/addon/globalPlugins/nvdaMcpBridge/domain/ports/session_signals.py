# nvdaMcpBridge domain -- the SessionSignals port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port, audible cues that the bridge has taken or released NVDA, heard even in silent mode.
# USED BY: the Session controller.
# IMPLEMENTED BY: adapters/nvda_session_signals.py; tests/fakes/session_signals.py.

from __future__ import annotations

from abc import ABC, abstractmethod


class SessionSignals(ABC):
	@abstractmethod
	def session_started(self, persona: str) -> None:
		"""Two ascending tones, then ``persona`` spoken as received; empty means the tones alone."""

	@abstractmethod
	def session_ended(self) -> None:
		"""Two descending tones: control has been released."""
