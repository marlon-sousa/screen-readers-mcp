# nvdaMcpBridge adapters -- cue_and_speak: two beeps, then one spoken utterance.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: a tiny shared edge helper (imports NVDA's tones and synth, plus wx), on
#       pyright's ignore list via the adapters/nvda_*.py glob.
# USED BY: NvdaAnnouncer (the announce hint, 660 Hz) and NvdaUserPrompter (an
#          askUser question, 440 Hz) -- the same "cue, then speak" gesture at two
#          pitches, so the tester can tell a question from a hint before any words
#          arrive. One helper rather than two copies, because the tricky parts
#          (speak past the suppression filter, space the beeps, keep the whole
#          thing on the main thread) are exactly the parts worth having once.
#
# Speaks through getSynth().speak() rather than NVDA's speech pipeline, so the
# words are heard even while silent mode suppresses captured speech at the
# speak() filter (see nvda_silent_speech_source.py).
#
# The whole sequence is spoken in ONE speak() call, so the synth cannot interleave
# it with anything else and the order inside it is guaranteed rather than timed.
#
# Must run on NVDA's main thread: callers marshal with run_on_main.

from __future__ import annotations

from collections.abc import Sequence

import synthDriverHandler
import tones
import wx


def cue_and_speak(
	sequence: Sequence[str], *, hz: int, ms: int, gap_ms: int, second_hz: int | None = None
) -> None:
	"""Beep twice at ``hz``, then speak ``sequence`` through the live synth.

	The beeps are scheduled ``gap_ms`` apart so both are clearly heard, and the
	speech follows them. Call on NVDA's main thread.

	``second_hz`` pitches the second beep differently, which is how the session
	cue says *ascending* (spec 0029): the pair already meant "the bridge has taken
	control", and the utterance after it says what the session is standing in for.
	Defaults to ``hz``, so the announce and askUser cues are unchanged.
	"""
	tones.beep(hz, ms)
	wx.CallLater(gap_ms, tones.beep, second_hz if second_hz is not None else hz, ms)

	def _speak() -> None:
		synth = synthDriverHandler.getSynth()
		if synth is not None:
			synth.speak(list(sequence))

	wx.CallLater(gap_ms * 2, _speak)
