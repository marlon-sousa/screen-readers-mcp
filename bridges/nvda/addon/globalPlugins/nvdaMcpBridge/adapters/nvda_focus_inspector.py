# nvdaMcpBridge adapters -- NvdaFocusInspector: read the focus object.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing FocusInspector.
# BUILT BY: adapters/nvda_adapter_factory.py.
# USED BY: the GetFocusInfoHandler.
# Every NVDA read is marshalled to the main thread. Roles and states are sent as enum names, never as
# localized strings.

from __future__ import annotations

import api
import controlTypes

from ..domain.ports.focus_inspector import FocusInfo, FocusInspector
from .nvda_main_thread import run_on_main


class NvdaFocusInspector(FocusInspector):
	def focus_info(self) -> FocusInfo:
		return run_on_main(self._read_focus, block=True)

	@staticmethod
	def _read_focus() -> FocusInfo:
		obj = api.getFocusObject()
		if obj is None:
			return FocusInfo(name="", role="", states=[], value=None, app_module=None)

		# An unrecognized role is sent as its decimal string.
		role: str
		try:
			role = controlTypes.Role(obj.role).name
		except (ValueError, TypeError):
			role = str(int(obj.role)) if obj.role is not None else ""

		states: list[str] = []
		if hasattr(obj, "states") and obj.states:
			for s in obj.states:
				try:
					states.append(controlTypes.State(s).name)
				except (ValueError, TypeError):
					states.append(str(int(s)))

		value: str | None = None
		if hasattr(obj, "value") and obj.value is not None:
			value = str(obj.value) if not isinstance(obj.value, str) else obj.value

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
