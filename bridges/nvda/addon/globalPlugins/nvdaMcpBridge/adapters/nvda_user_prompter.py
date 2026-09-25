# nvdaMcpBridge adapters -- NvdaUserPrompter: present prompts to the human.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing UserPrompter: a cue, then the question and instruction, via the live synth.
# BUILT BY: plugin.py.
# USED BY: AskUserHandler and session teardown.

from __future__ import annotations

from ..domain.ports.user_prompter import UserPrompter
from .nvda_cue import cue_and_speak
from .nvda_main_thread import run_on_main

_PROMPT_CUE_HZ = 440
_PROMPT_CUE_MS = 100
_PROMPT_CUE_GAP_MS = 160

#: The default acknowledgement gesture: plugin.py binds it and the spoken instruction names it, so a
#: user who rebinds the script still hears this default.
ACK_GESTURE = "NVDA+control+shift+a"


class NvdaUserPrompter(UserPrompter):
	def present(self, prompt: str, ticket: str) -> None:
		# Translators: Spoken after an agent's question, naming the gesture that
		# answers it. {gesture} is a key combination, e.g. "NVDA control shift a".
		instruction = _("Press {gesture} when you are done.").format(gesture=ACK_GESTURE.replace("+", " "))
		run_on_main(
			lambda: cue_and_speak(
				[prompt, " ", instruction],
				hz=_PROMPT_CUE_HZ,
				ms=_PROMPT_CUE_MS,
				gap_ms=_PROMPT_CUE_GAP_MS,
			)
		)

	def cancel(self, ticket: str) -> None:
		# There is no dialog to close.
		pass
