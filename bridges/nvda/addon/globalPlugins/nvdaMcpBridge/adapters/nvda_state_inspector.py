# nvdaMcpBridge adapters -- NvdaStateInspector: read the reader's mode-state.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing StateInspector.
# BUILT BY: adapters/nvda_adapter_factory.py.
# USED BY: the GetStateHandler.
# Every NVDA read is marshalled to the main thread.

from __future__ import annotations

import api
import inputCore
import speech

from ..domain.ports.state_inspector import ReaderState, StateInspector
from .nvda_main_thread import run_on_main


class NvdaStateInspector(StateInspector):
	def state(self) -> ReaderState:
		return run_on_main(self._read_state, block=True)

	@staticmethod
	def _read_state() -> ReaderState:
		speech_mode = speech.getState().speechMode.name

		focus = api.getFocusObject()
		sleep_mode = bool(focus.sleepMode) if focus is not None and hasattr(focus, "sleepMode") else False

		input_help = bool(inputCore.manager.isInputHelpActive)

		browse_mode = _derive_browse_mode(focus)

		return ReaderState(
			browse_mode=browse_mode,
			speech_mode=speech_mode,
			sleep_mode=sleep_mode,
			input_help=input_help,
		)


def _derive_browse_mode(focus: object) -> str:
	"""Reads treeInterceptor.passThrough, as NVDA's own browseMode.reportPassThrough does."""
	if focus is None or not hasattr(focus, "treeInterceptor"):
		return "none"
	ti = focus.treeInterceptor  # type: ignore[union-attr]
	if ti is None:
		return "none"
	if not hasattr(ti, "passThrough"):
		return "none"
	return "focus" if bool(ti.passThrough) else "browse"  # type: ignore[union-attr]
