# nvdaMcpBridge adapters -- cue_and_speak: two beeps, then one spoken utterance.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: shared edge helper that beeps, then speaks through the live synth.
# USED BY: NvdaAnnouncer and NvdaUserPrompter.
# getSynth().speak() bypasses the speak() filter, so the words are heard while silent mode suppresses
# captured speech. The sequence goes in one speak() call so the synth cannot interleave anything with it.
# Must run on NVDA's main thread.

from __future__ import annotations

from collections.abc import Sequence

import synthDriverHandler
import tones
import wx


def cue_and_speak(
	sequence: Sequence[str], *, hz: int, ms: int, gap_ms: int, second_hz: int | None = None
) -> None:
	tones.beep(hz, ms)
	wx.CallLater(gap_ms, tones.beep, second_hz if second_hz is not None else hz, ms)

	def _speak() -> None:
		synth = synthDriverHandler.getSynth()
		if synth is not None:
			synth.speak(list(sequence))

	wx.CallLater(gap_ms * 2, _speak)
