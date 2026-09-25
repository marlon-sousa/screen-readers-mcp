# nvdaMcpBridge tests -- FakeFocusInspector, standing in for the FocusInspector port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from nvdaMcpBridge.domain.ports.focus_inspector import FocusInfo, FocusInspector


class FakeFocusInspector(FocusInspector):
	def __init__(self) -> None:
		self.calls: list[None] = []
		self.info: FocusInfo = FocusInfo(
			name="Test Button",
			role="BUTTON",
			states=["FOCUSABLE", "FOCUSED"],
			value=None,
			app_module="test_app",
		)

	def focus_info(self) -> FocusInfo:
		self.calls.append(None)
		return self.info
