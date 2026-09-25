# nvdaMcpBridge adapters -- NvdaStateSetter: arrive at a reader mode, idempotently.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing StateSetter through NVDA's own browse-mode path, never a synthetic NVDA+space.
# BUILT BY: adapters/nvda_adapter_factory.py.
# USED BY: the SetStateHandler.
# The read and the write happen in one main-thread step, so a page that finishes loading cannot flip the
# mode between them. Already in the target mode does nothing, so no focus-mode tone plays; a change calls
# reportPassThrough so the user hears what their own keypress would produce.
# Unlike NVDA's script it never forces a treeInterceptor into existence; no document raises StateSetError.

from __future__ import annotations

import api
import browseMode

from ..domain.ports.state_setter import StateSetError, StateSetter
from .nvda_main_thread import run_on_main

_PASS_THROUGH: dict[str, bool] = {"focus": True, "browse": False}

_NOT_A_DOCUMENT = "the focused object is not a browsable document"


class NvdaStateSetter(StateSetter):
	def set_browse_mode(self, target: str) -> bool:
		want = _PASS_THROUGH[target]
		return bool(run_on_main(lambda: self._apply(want), block=True))

	@staticmethod
	def _apply(want_pass_through: bool) -> bool:
		focus = api.getFocusObject()
		buffer = getattr(focus, "treeInterceptor", None) if focus is not None else None
		if buffer is None or not isinstance(buffer, browseMode.BrowseModeTreeInterceptor):
			raise StateSetError(_NOT_A_DOCUMENT)

		if bool(buffer.passThrough) == want_pass_through:
			return False

		buffer.passThrough = want_pass_through
		# As NVDA's script does: explicit focus mode disables auto pass-through, leaving it re-enables it.
		buffer.disableAutoPassThrough = buffer.passThrough
		browseMode.reportPassThrough(buffer)
		return True
