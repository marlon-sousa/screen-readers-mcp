# nvdaMcpBridge adapters -- NvdaStateInspector: read the reader's mode-state.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the StateInspector port. On pyright's ignore list
#       (imports NVDA); validated by the 11.1 live-NVDA checklist.
# BUILT BY: adapters/nvda_adapter_factory.py.
# USED BY: the GetStateHandler.
#
# All NVDA reads are marshalled to the main thread. The browse-mode tri-state is
# derived from the focus object's treeInterceptor, matching NVDA's own
# browseMode.reportPassThrough behaviour (spec 0015):
#   "browse" -- the focus has a TreeInterceptor with passThrough False.
#   "focus"  -- the focus has a TreeInterceptor with passThrough True.
#   "none"   -- the focus has no TreeInterceptor at all.

from __future__ import annotations

import api
import inputCore
import speech

from ..domain.ports.state_inspector import ReaderState, StateInspector
from .nvda_main_thread import run_on_main


class NvdaStateInspector(StateInspector):
    """Reads speech mode, sleep mode, input help, and browse mode on NVDA's main thread."""

    def state(self) -> ReaderState:
        return run_on_main(self._read_state, block=True)

    @staticmethod
    def _read_state() -> ReaderState:
        # Speech mode: speech.getState().speechMode.name -- one of "off", "beeps",
        # "talk", "onDemand". Re-exported from speech/__init__.py.
        speech_mode = speech.getState().speechMode.name

        # Sleep mode from the focus object (api.getFocusObject().sleepMode).
        focus = api.getFocusObject()
        sleep_mode = bool(focus.sleepMode) if focus is not None and hasattr(focus, "sleepMode") else False

        # Input help: True while NVDA+1 is active (gestures described, not performed).
        input_help = bool(inputCore.manager.isInputHelpActive)

        # Browse mode: tri-state derivation from the focus object's treeInterceptor.
        browse_mode = _derive_browse_mode(focus)

        return ReaderState(
            browse_mode=browse_mode,
            speech_mode=speech_mode,
            sleep_mode=sleep_mode,
            input_help=input_help,
        )


def _derive_browse_mode(focus: object) -> str:
    """Derive the browse/focus/none tri-state from the focus object.

    NVDA's own ``browseMode.reportPassThrough`` reads
    ``treeInterceptor.passThrough``, so:
    - No treeInterceptor at all → ``"none"`` (neither mode applies).
    - Has a treeInterceptor, passThrough is False → ``"browse"``.
    - Has a treeInterceptor, passThrough is True → ``"focus"``.
    """
    if focus is None or not hasattr(focus, "treeInterceptor"):
        return "none"
    ti = focus.treeInterceptor  # type: ignore[union-attr]
    if ti is None:
        return "none"
    if not hasattr(ti, "passThrough"):
        return "none"
    return "focus" if bool(ti.passThrough) else "browse"  # type: ignore[union-attr]
