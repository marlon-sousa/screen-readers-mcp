# nvdaMcpBridge domain -- the SessionSignals port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: domain port. Audible cues for the human at the keyboard that the bridge
#       has taken / released control of NVDA -- so they land even in silent mode,
#       when speech is captured and inaudible.
# USED BY: the Session controller (start of an established session, and teardown).
# IMPLEMENTED BY: adapters/nvda_session_signals.py (NVDA tones);
#                 tests/fakes/session_signals.py FakeSessionSignals.
#
# Tones, not the ordinary speech pipeline: they must be heard while speech is
# being suppressed. The on/off toggle is entry 9.1's config dialog; the default
# is on.

from __future__ import annotations

from abc import ABC, abstractmethod


class SessionSignals(ABC):
	"""Audible cues marking when the bridge starts and stops controlling NVDA."""

	@abstractmethod
	def session_started(self, persona: str) -> None:
		"""Two ascending tones, then the session's persona spoken (spec 0029).

		The tones say that *something* has taken the reader; they cannot say what
		it is standing in for, and the person sitting there deserves to know
		which. ``persona`` is spoken as received -- an implementation does not
		have to recognise a value in order to say it, and a human hearing an
		unfamiliar word is better served than a human hearing nothing. Empty
		means the server declared none (an older one), and then this is exactly
		the tones it always was.
		"""

	@abstractmethod
	def session_ended(self) -> None:
		"""Two descending tones: control has been released."""
