# nvdaMcpBridge adapters -- RealClock: the production Clock.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: leaf adapter implementing Clock with the stdlib clock.
# BUILT BY: wiring and plugin.py.

from __future__ import annotations

import time

from ..domain.ports.clock import Clock


class RealClock(Clock):
	def monotonic(self) -> float:
		return time.monotonic()

	def sleep(self, seconds: float) -> None:
		time.sleep(seconds)

	def time(self) -> float:
		return time.time()
