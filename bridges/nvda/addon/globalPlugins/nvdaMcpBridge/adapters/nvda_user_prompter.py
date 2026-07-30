# nvdaMcpBridge adapters -- NvdaUserPrompter: present prompts to the human.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the UserPrompter port. On pyright's ignore list
#       (imports NVDA); validated by the 11.2 live-NVDA checklist.
# BUILT BY: plugin.py (once) and injected via wiring.build_session.
# USED BY: AskUserHandler (present), session teardown (cancel).
#
# present(): two cue beeps distinct from the announce cue, then the prompt and the
# instruction naming the acknowledgement gesture, spoken as ONE utterance through
# the real synth (see nvda_cue.py -- shared with the announcer). The beeps are
# lower-pitched than the announce cue (440 Hz vs 660 Hz) so the tester can tell "a
# question" from "a hint" before the speech starts.
#
# cancel() is a no-op in stage 1 (there is no dialog to close). It exists as a
# port method so stage 2 can add dialog cleanup without changing its callers --
# the session's teardown path already calls it.

from __future__ import annotations

from ..domain.ports.user_prompter import UserPrompter
from .nvda_cue import cue_and_speak
from .nvda_main_thread import run_on_main

# Distinct from the announce cue (660 Hz) so the tester can tell a question
# from a hint before the speech starts.
_PROMPT_CUE_HZ = 440
_PROMPT_CUE_MS = 100
_PROMPT_CUE_GAP_MS = 160

#: The DEFAULT gesture for acknowledging a prompt, and the single place the key
#: combination is written down: plugin.py binds its script to this string and the
#: spoken instruction is built from it, so the two cannot drift apart. A user who
#: rebinds the script in Input Gestures still hears the default named here --
#: reading the live binding back out of inputCore is stage-2 work, and hearing the
#: default is better than hearing no key at all.
ACK_GESTURE = "NVDA+control+shift+a"


class NvdaUserPrompter(UserPrompter):
	"""Presents prompts audibly and acknowledges via a gesture."""

	def present(self, prompt: str, ticket: str) -> None:
		# Translators: Spoken after an agent's question, naming the gesture that
		# answers it. {gesture} is a key combination, e.g. "NVDA control shift a".
		instruction = _("Press {gesture} when you are done.").format(
			gesture=ACK_GESTURE.replace("+", " ")
		)
		# One utterance, so the synth cannot put the instruction before the
		# question or interleave the two.
		run_on_main(
			lambda: cue_and_speak(
				[prompt, " ", instruction],
				hz=_PROMPT_CUE_HZ,
				ms=_PROMPT_CUE_MS,
				gap_ms=_PROMPT_CUE_GAP_MS,
			)
		)

	def cancel(self, ticket: str) -> None:
		# Stage 1 has no dialog to close; stage 2 will add cleanup here.
		pass
