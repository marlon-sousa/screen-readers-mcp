# nvdaMcpBridge adapters -- NvdaSessionSignals: the start/end session beeps.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the SessionSignals port with NVDA's `tones`. On
#       pyright's ignore list (imports NVDA).
# BUILT BY: plugin.py (once) and injected via wiring.build_session.
# USED BY: the Session -- ascending pair when a session establishes, descending
#          pair at teardown. Tones (not speech) so they are heard even in silent
#          mode, when captured speech is suppressed.
#
# Marshalled to NVDA's main thread, like every other NVDA touch here.
#
# The start cue also SPEAKS the session's persona (spec 0029). The tones say that
# something has taken the reader; they cannot say what it is standing in for, and
# the person sitting at the machine deserves to know which. It goes through the
# live synth directly -- the same route cue_and_speak uses -- so it is heard while
# silent mode is suppressing captured speech at the speak() filter.

from __future__ import annotations

import tones
import wx

from ..domain.ports.session_signals import SessionSignals
from .nvda_cue import cue_and_speak
from .nvda_main_thread import run_on_main

_LOW_HZ = 440
_HIGH_HZ = 660
_TONE_MS = 180
#: Start-to-start spacing of the two tones. Must exceed _TONE_MS so the first
#: tone finishes (and is audible) before the second starts on the same player --
#: back-to-back beeps swallowed the first.
_GAP_MS = 300


class NvdaSessionSignals(SessionSignals):
	"""Two spaced ascending tones on start, two descending on end."""

	def session_started(self, persona: str) -> None:
		run_on_main(lambda: self._started(persona))

	def session_ended(self) -> None:
		run_on_main(lambda: self._pair(_HIGH_HZ, _LOW_HZ))

	@classmethod
	def _started(cls, persona: str) -> None:
		if not persona:
			# An older server declared nothing to say. Then this is exactly the
			# pair of tones it has always been.
			cls._pair(_LOW_HZ, _HIGH_HZ)
			return
		# Translators: spoken when an MCP session starts, naming what the agent
		# declared it is standing in for (for example "user" or "validator").
		spoken = _("MCP session open, as {persona}").format(persona=persona)
		# The shared helper, so "speak past the suppression filter" has one
		# definition rather than a second copy here (see nvda_cue.py). The
		# persona is spoken as received: this adapter does not have to recognise
		# a value in order to say it.
		cue_and_speak([spoken], hz=_LOW_HZ, second_hz=_HIGH_HZ, ms=_TONE_MS, gap_ms=_GAP_MS)

	@staticmethod
	def _pair(first_hz: int, second_hz: int) -> None:
		tones.beep(first_hz, _TONE_MS)
		# Schedule the second tone after a gap so the first is fully heard.
		wx.CallLater(_GAP_MS, tones.beep, second_hz, _TONE_MS)
