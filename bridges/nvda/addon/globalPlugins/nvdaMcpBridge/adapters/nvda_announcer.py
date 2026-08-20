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

from ..domain.ports.announcer import Announcer, SilenceNotice
from .nvda_cue import cue_and_speak
from .nvda_main_thread import run_on_main

_CUE_HZ = 660
_CUE_MS = 100
#: Spacing between the two cue beeps (and before the speech), so both beeps are
#: clearly heard before the hint is spoken.
_CUE_GAP_MS = 160

#: The silence cap's own pitch (spec 0032, chosen by the maintainer at the
#: keyboard on 2026-08-19). An octave above askUser's 440 Hz and a fourth above
#: announce's 660 Hz -- the highest of the three, so it reads as "attention"
#: rather than as a hint or a question, and it is tellable from both BEFORE any
#: word arrives. That is the whole point: this notice is the bridge speaking about
#: the agent's silence, and it must not sound like the agent.
_CAP_CUE_HZ = 880


class NvdaAnnouncer(Announcer):
	"""Reads the real synth's name and speaks hints straight through it."""

	def current_synth(self) -> str:
		return run_on_main(self._read_name, block=True) or ""

	def announce(self, text: str) -> None:
		run_on_main(lambda: cue_and_speak([text], hz=_CUE_HZ, ms=_CUE_MS, gap_ms=_CUE_GAP_MS))

	def silence_notice(self, notice: SilenceNotice) -> None:
		text = _SILENCE_NOTICES[notice]()
		run_on_main(lambda: cue_and_speak([text], hz=_CAP_CUE_HZ, ms=_CUE_MS, gap_ms=_CUE_GAP_MS))

	@staticmethod
	def _read_name() -> str:
		synth = synthDriverHandler.getSynth()
		return synth.name if synth is not None else ""


#: What each silence-cap notice SAYS, in the reader's own language. Callables
#: rather than strings so translation happens when the notice is spoken, not when
#: this module is imported -- NVDA installs `_` before add-ons load, but a language
#: change mid-session would otherwise be frozen out.
#:
#: The wording names no number. The thresholds are configurable per machine, and a
#: sentence promising "45 seconds" on a box configured otherwise would be worse
#: than one that promises nothing.
_SILENCE_NOTICES = {
	# Translators: Spoken when a silent MCP session has told the human nothing for
	# a while; speech will be restored shortly if that continues.
	SilenceNotice.WARNING: lambda: _(
		"The agent has not spoken to you for a while. Speech will be restored shortly."
	),
	# Translators: Spoken when the silence cap has ended speech suppression. The
	# session itself continues.
	SilenceNotice.LIFTED: lambda: _("Speech restored. The MCP session is still running."),
	# Translators: Spoken when a session that the silence cap had un-muted goes
	# quiet again.
	SilenceNotice.RESUPPRESSED: lambda: _("Speech suppressed again."),
}
