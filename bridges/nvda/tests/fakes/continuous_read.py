# nvdaMcpBridge tests -- FakeContinuousRead, standing in for the ContinuousRead port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from nvdaMcpBridge.domain.ports.continuous_read import ContinuousRead


class FakeContinuousRead(ContinuousRead):
	def __init__(self, *, running: bool = False) -> None:
		self.running = running
		self.asked = 0

	def in_progress(self) -> bool:
		self.asked += 1
		return self.running
