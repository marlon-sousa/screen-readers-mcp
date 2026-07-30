# nvdaMcpBridge adapters -- NvdaAnnouncer: the bridge's line to the real synth.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the Announcer port. On pyright's ignore list (imports
#       NVDA); validated by the 9c live-NVDA checklist.
# BUILT BY: plugin.py (once) and injected via wiring.build_session.
# USED BY: the hello handler (current_synth for the handshake) and the
#          AnnounceHandler (announce the bridge->human hint).
#
# The reader's real synth stays loaded in every mode (silent mode suppresses at
# NVDA's speak() filter, not by swapping the synth). So:
#   * current_synth() just reads synthDriverHandler.getSynth().name.
#   * announce() speaks straight through that live synth via getSynth().speak(),
#     which bypasses the speak() suppression filter entirely -- so the hint is
#     heard even while normal captured speech is muted. Two short beeps precede it
#     as a "hint incoming" cue (Marlon's request). That cue-then-speak gesture
#     lives in nvda_cue.py, shared with NvdaUserPrompter, which needs the same
#     thing one pitch lower.
# All NVDA touches are marshalled to the main thread.

from __future__ import annotations

import synthDriverHandler

from ..domain.ports.announcer import Announcer
from .nvda_cue import cue_and_speak
from .nvda_main_thread import run_on_main

_CUE_HZ = 660
_CUE_MS = 100
#: Spacing between the two cue beeps (and before the speech), so both beeps are
#: clearly heard before the hint is spoken.
_CUE_GAP_MS = 160


class NvdaAnnouncer(Announcer):
	"""Reads the real synth's name and speaks hints straight through it."""

	def current_synth(self) -> str:
		return run_on_main(self._read_name, block=True) or ""

	def announce(self, text: str) -> None:
		run_on_main(
			lambda: cue_and_speak([text], hz=_CUE_HZ, ms=_CUE_MS, gap_ms=_CUE_GAP_MS)
		)

	@staticmethod
	def _read_name() -> str:
		synth = synthDriverHandler.getSynth()
		return synth.name if synth is not None else ""
