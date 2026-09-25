# nvdaMcpBridge tests -- FakeStateSetter, standing in for the StateSetter port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# Compares inside itself, as the real adapter compares inside NVDA.

from __future__ import annotations

import dataclasses

from nvdaMcpBridge.domain.ports.state_setter import StateSetError, StateSetter

from .state_inspector import FakeStateInspector


class FakeStateSetter(StateSetter):
	def __init__(self, browse_mode: str = "browse", inspector: FakeStateInspector | None = None) -> None:
		self.browse_mode = browse_mode
		#: When wired, a successful write shows up in what the inspector reports.
		self._inspector = inspector
		#: Every target asked for, including ones that changed nothing.
		self.calls: list[str] = []
		self.writes: list[str] = []
		self.fail_with: str | None = None

	def set_browse_mode(self, target: str) -> bool:
		self.calls.append(target)
		if self.fail_with is not None:
			raise StateSetError(self.fail_with)
		if self.browse_mode == target:
			return False
		self.browse_mode = target
		self.writes.append(target)
		if self._inspector is not None:
			self._inspector.reader_state = dataclasses.replace(
				self._inspector.reader_state, browse_mode=target
			)
		return True
