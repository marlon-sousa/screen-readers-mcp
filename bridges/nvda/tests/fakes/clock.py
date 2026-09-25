# nvdaMcpBridge tests -- FakeClock, standing in for the Clock port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from nvdaMcpBridge.domain.ports.clock import Clock


class FakeClock(Clock):
	"""Time moves only on demand; sleep is an instant advance."""

	def __init__(self, start: float = 0.0) -> None:
		self._now = start
		self.sleeps: list[float] = []

	def monotonic(self) -> float:
		return self._now

	def sleep(self, seconds: float) -> None:
		self.sleeps.append(seconds)
		self._now += seconds

	def advance(self, seconds: float) -> None:
		self._now += seconds

	def time(self) -> float:
		# Shares monotonic()'s counter: tests compare only differences between the two clocks.
		return self._now
