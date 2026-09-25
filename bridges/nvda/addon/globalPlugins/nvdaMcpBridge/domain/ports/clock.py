# nvdaMcpBridge domain -- the Clock port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port, what the domain needs from the world about time.
# IMPLEMENTED BY: adapters/real_clock.py; tests/fakes/clock.py.
# USED BY: the buffer entities and the Session's watchdogs.

from __future__ import annotations

from abc import ABC, abstractmethod


class Clock(ABC):
	@abstractmethod
	def monotonic(self) -> float:
		"""Seconds from an arbitrary origin; only differences matter."""

	@abstractmethod
	def sleep(self, seconds: float) -> None:
		"""A fake may make this an instant clock advance."""

	@abstractmethod
	def time(self) -> float:
		"""Wall-clock epoch seconds, the same epoch as a log record's ``created``."""
