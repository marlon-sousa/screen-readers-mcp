# nvdaMcpBridge adapters -- NvdaAnnouncer: the bridge's line to the real synth.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing the Announcer port.
# BUILT BY: plugin.py.
# USED BY: the hello handler and AnnounceHandler.
# Every NVDA call is marshalled to the main thread.

from __future__ import annotations

import synthDriverHandler

from ..domain.ports.announcer import Announcer, SilenceNotice
from .nvda_cue import cue_and_speak
from .nvda_main_thread import run_on_main

_CUE_HZ = 660
_CUE_MS = 100
_CUE_GAP_MS = 160

#: Higher than the announce and askUser cues, so the bridge's notice never sounds like the agent.
_CAP_CUE_HZ = 880


class NvdaAnnouncer(Announcer):
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


#: Callables so translation happens when a notice is spoken, not when this module is imported.
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
