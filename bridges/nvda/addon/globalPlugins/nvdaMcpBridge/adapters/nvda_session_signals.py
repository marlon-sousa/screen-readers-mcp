# nvdaMcpBridge adapters -- NvdaSessionSignals: the start/end session beeps.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing SessionSignals: ascending tones and the persona on start, descending at teardown.
# BUILT BY: plugin.py.
# USED BY: the Session.
# Marshalled to NVDA's main thread.

from __future__ import annotations

import tones
import wx

from ..domain.ports.session_signals import SessionSignals
from .nvda_cue import cue_and_speak
from .nvda_main_thread import run_on_main

_LOW_HZ = 440
_HIGH_HZ = 660
_TONE_MS = 180
#: Must exceed _TONE_MS: back-to-back beeps on the same player swallow the first.
_GAP_MS = 300


class NvdaSessionSignals(SessionSignals):
	def session_started(self, persona: str) -> None:
		run_on_main(lambda: self._started(persona))

	def session_ended(self) -> None:
		run_on_main(lambda: self._pair(_HIGH_HZ, _LOW_HZ))

	@classmethod
	def _started(cls, persona: str) -> None:
		if not persona:
			cls._pair(_LOW_HZ, _HIGH_HZ)
			return
		# Translators: spoken when an MCP session starts, naming what the agent
		# declared it is standing in for (for example "user" or "validator").
		spoken = _("MCP session open, as {persona}").format(persona=persona)
		cue_and_speak([spoken], hz=_LOW_HZ, second_hz=_HIGH_HZ, ms=_TONE_MS, gap_ms=_GAP_MS)

	@staticmethod
	def _pair(first_hz: int, second_hz: int) -> None:
		tones.beep(first_hz, _TONE_MS)
		wx.CallLater(_GAP_MS, tones.beep, second_hz, _TONE_MS)
