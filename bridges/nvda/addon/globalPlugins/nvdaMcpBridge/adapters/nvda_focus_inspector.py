# nvdaMcpBridge adapters -- NvdaFocusInspector: read the focus object.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the FocusInspector port. On pyright's ignore list
#       (imports NVDA); validated by the 11.1 live-NVDA checklist.
# BUILT BY: adapters/nvda_adapter_factory.py.
# USED BY: the GetFocusInfoHandler.
#
# All NVDA reads are marshalled to the main thread. Role and state names are sent
# as stable enum .name values (e.g. "BUTTON", "FOCUSED"), not as localized display
# strings, so an assertion passes regardless of the tester's NVDA language
# (spec 0015). A null focus yields an empty FocusInfo rather than raising -- the
# agent can check for it with a normal assertion.

from __future__ import annotations

import api
import controlTypes

from ..domain.ports.focus_inspector import FocusInfo, FocusInspector
from .nvda_main_thread import run_on_main


class NvdaFocusInspector(FocusInspector):
	"""Reads api.getFocusObject() on NVDA's main thread."""

	def focus_info(self) -> FocusInfo:
		return run_on_main(self._read_focus, block=True)

	@staticmethod
	def _read_focus() -> FocusInfo:
		obj = api.getFocusObject()
		if obj is None:
			return FocusInfo(name="", role="", states=[], value=None, app_module=None)

		# Role: send the stable enum .name. An unrecognized role (a raw int NVDA
		# has no member for) is sent as its decimal string rather than dropped.
		role: str
		try:
			role = controlTypes.Role(obj.role).name
		except (ValueError, TypeError):
			role = str(int(obj.role)) if obj.role is not None else ""

		# States: each is a controlTypes.State member's .name.
		states: list[str] = []
		if hasattr(obj, "states") and obj.states:
			for s in obj.states:
				try:
					states.append(controlTypes.State(s).name)
				except (ValueError, TypeError):
					states.append(str(int(s)))

		# Value: the accessible value if present (e.g. "75" for a slider).
		value: str | None = None
		if hasattr(obj, "value") and obj.value is not None:
			value = str(obj.value) if not isinstance(obj.value, str) else obj.value

		# App module: the owning application's name.
		app_module: str | None = None
		if hasattr(obj, "appModule") and obj.appModule is not None:
			app_module = obj.appModule.appModuleName

		return FocusInfo(
			name=obj.name or "",
			role=role,
			states=states,
			value=value,
			app_module=app_module,
		)
