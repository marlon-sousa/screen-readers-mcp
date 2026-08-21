# nvdaMcpBridge adapters -- NvdaStateSetter: arrive at a reader mode, idempotently.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the StateSetter port. On pyright's ignore list
#       (imports NVDA); validated by the 11.17 live-NVDA checklist.
# BUILT BY: adapters/nvda_adapter_factory.py.
# USED BY: the SetStateHandler.
#
# IT TAKES NVDA'S OWN PATH, never a synthetic NVDA+space: the gesture is the
# thing under test, and pressing it to satisfy a precondition is what made the
# precondition unreliable in the first place (spec 0033 Part 1).
#
# The read and the write happen in ONE step on NVDA's main thread, which is the
# whole point of the command. Reading through the inspector, comparing in the
# domain and writing back here would leave a window between the two, and a page
# that finished loading inside that window flips the mode the wrong way -- the
# 2026-08-03 incident, one layer down and harder to see.
#
# Already-there does NOTHING AT ALL: no assignment, and above all no
# reportPassThrough, so no `focusMode.wav` and no "Focus mode". A human in a live
# session must not be made to listen to a tone every time an agent restates a
# precondition (spec 0033 Part 3.2).
#
# When it DOES change the mode it calls browseMode.reportPassThrough exactly as
# NVDA's own script does, so the human at the reader hears precisely what their
# reader would have said had they pressed the key themselves. An agent that
# changed a mode silently would be driving a reader its user cannot follow.
#
# ONE DELIBERATE NARROWING from NVDA's own script: globalCommands'
# script_toggleVirtualBufferPassThrough will, when the focus has no
# treeInterceptor, walk the ancestors and FORCE one into existence. This adapter
# does not. `browseMode: "none"` means there is no browsable document here, the
# tri-state exists to say so, and conjuring a buffer would make the setter answer
# a question the caller did not ask. It reports the obstacle instead.

from __future__ import annotations

import api
import browseMode

from ..domain.ports.state_setter import StateSetError, StateSetter
from .nvda_main_thread import run_on_main

#: What the wire's browse-mode values mean in NVDA's own terms: pass-through ON
#: is focus mode, pass-through OFF is browse mode (browseMode.reportPassThrough).
_PASS_THROUGH: dict[str, bool] = {"focus": True, "browse": False}

_NOT_A_DOCUMENT = "the focused object is not a browsable document"


class NvdaStateSetter(StateSetter):
	"""Sets browse/focus mode through NVDA's own browse-mode path, on its main thread."""

	def set_browse_mode(self, target: str) -> bool:
		want = _PASS_THROUGH[target]
		return bool(run_on_main(lambda: self._apply(want), block=True))

	@staticmethod
	def _apply(want_pass_through: bool) -> bool:
		focus = api.getFocusObject()
		buffer = getattr(focus, "treeInterceptor", None) if focus is not None else None
		if buffer is None or not isinstance(buffer, browseMode.BrowseModeTreeInterceptor):
			# The specific obstacle, in the terms the agent has to act on. A bare
			# failure here is what sends an agent looking in the application it is
			# testing rather than at the reader it is driving (spec 0027's run).
			raise StateSetError(_NOT_A_DOCUMENT)

		if bool(buffer.passThrough) == want_pass_through:
			return False

		buffer.passThrough = want_pass_through
		# NVDA's own script's reasoning, kept verbatim in effect: choosing focus
		# mode explicitly disables auto-pass-through, and leaving it re-enables
		# auto-pass-through. Skipping this would leave the reader in a state no
		# keypress can produce, which is precisely what "simulates a user" forbids.
		buffer.disableAutoPassThrough = buffer.passThrough
		browseMode.reportPassThrough(buffer)
		return True
