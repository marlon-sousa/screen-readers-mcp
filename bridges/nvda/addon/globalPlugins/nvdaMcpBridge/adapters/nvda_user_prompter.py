# nvdaMcpBridge adapters -- NvdaUserPrompter: present prompts to the human.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the UserPrompter port. On pyright's ignore list
#       (imports NVDA); validated by the 11.2 live-NVDA checklist.
# BUILT BY: plugin.py (once) and injected via wiring.build_session.
# USED BY: AskUserHandler (present), session teardown (cancel).
#
# present(): two cue beeps distinct from the announce cue, then the prompt spoken
# through the real synth, then a spoken instruction naming the acknowledgement
# gesture. All via run_on_main. The beeps are lower-pitched than the announce cue
# (440 Hz vs 660 Hz) so the tester can tell "a question" from "a hint" before the
# speech starts.
#
# cancel() is a no-op in stage 1 (there is no dialog to close). It exists as a
# port method so stage 2 can add dialog cleanup without changing the caller.

from __future__ import annotations

import synthDriverHandler
import tones
import wx

from ..domain.ports.user_prompter import UserPrompter
from .nvda_main_thread import run_on_main

# Distinct from the announce cue (660 Hz) so the tester can tell a question
# from a hint before the speech starts.
_PROMPT_CUE_HZ = 440
_PROMPT_CUE_MS = 100
_PROMPT_CUE_GAP_MS = 160

#: The default gesture for acknowledging a prompt. In the same scriptCategory
#: as the panic gesture so it appears in Input Gestures and is rebindable.
_ACK_GESTURE = "NVDA+control+shift+a"


class NvdaUserPrompter(UserPrompter):
    """Presents prompts audibly and acknowledges via a gesture."""

    def present(self, prompt: str, ticket: str) -> None:
        run_on_main(lambda: self._cue_and_present(prompt))

    def cancel(self, ticket: str) -> None:
        # Stage 1 has no dialog to close; stage 2 will add cleanup here.
        pass

    @staticmethod
    def _cue_and_present(prompt: str) -> None:
        # Two spaced low beeps, then speak the prompt through the live synth,
        # then speak the instruction. All queued so the beeps finish before
        # speech starts, and the prompt finishes before the instruction.
        tones.beep(_PROMPT_CUE_HZ, _PROMPT_CUE_MS)
        wx.CallLater(_PROMPT_CUE_GAP_MS, tones.beep, _PROMPT_CUE_HZ, _PROMPT_CUE_MS)

        def _speak_prompt() -> None:
            synth = synthDriverHandler.getSynth()
            if synth is not None:
                synth.speak([prompt])

        wx.CallLater(_PROMPT_CUE_GAP_MS * 2, _speak_prompt)

        def _speak_instruction() -> None:
            synth = synthDriverHandler.getSynth()
            if synth is not None:
                synth.speak([
                    "Press NVDA control shift A when you are done."
                ])

        wx.CallLater(_PROMPT_CUE_GAP_MS * 3, _speak_instruction)
