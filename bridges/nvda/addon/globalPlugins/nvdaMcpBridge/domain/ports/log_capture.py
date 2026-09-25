# nvdaMcpBridge domain -- the LogCapture port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port, a private session-scoped journal of NVDA's own diagnostic log.
# USED BY: the hello handler, the log command handlers, and the Session, which brackets each command.
# IMPLEMENTED BY: adapters/nvda_log_capture.py; tests/fakes/log_capture.py.
# A level is a real change to NVDA's logging, so it only works forwards.
# ``stop`` restores the prior level and must be safe even if ``start`` was never reached.

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING

if TYPE_CHECKING:
	from ... import protocol


class LogCapture(ABC):
	@abstractmethod
	def start(self, level: protocol.LogLevel | None) -> None: ...

	@abstractmethod
	def stop(self) -> None: ...

	@property
	@abstractmethod
	def current_level(self) -> protocol.LogLevel:
		"""For ``capturedAtLevel`` reporting."""

	@abstractmethod
	def set_level(self, level: protocol.LogLevel) -> None:
		"""Only ``log_journal.SETTABLE_LEVELS`` reach here."""

	@abstractmethod
	def position(self) -> int:
		"""The journal's current append position."""

	@abstractmethod
	def slice(
		self,
		start: int,
		end: int,
		*,
		min_level: protocol.LogLevel | None = None,
		contains: list[str] | None = None,
		exclude: list[str] | None = None,
		fields: list[str] | None = None,
		max_entries: int = 200,
	) -> tuple[str, int, int, bool]:
		"""Returns ``(text, entries, matched, truncated)``; the caller owns the command ids."""

	@abstractmethod
	def slice_since(
		self,
		position: int,
		*,
		min_level: protocol.LogLevel | None = None,
		contains: list[str] | None = None,
		exclude: list[str] | None = None,
		fields: list[str] | None = None,
		max_entries: int = 200,
	) -> tuple[str, int, int, bool]:
		"""``slice(position, now)``."""

	@abstractmethod
	def slice_last_seconds(
		self,
		seconds: float,
		*,
		min_level: protocol.LogLevel | None = None,
		contains: list[str] | None = None,
		exclude: list[str] | None = None,
		fields: list[str] | None = None,
		max_entries: int = 200,
	) -> tuple[str, int, int, bool]:
		"""Everything in the last *seconds*."""

	@abstractmethod
	def find_since(
		self,
		start: int,
		*,
		min_level: protocol.LogLevel | None = None,
		contains: list[str] | None = None,
	) -> tuple[int, str] | None:
		"""``(position, text)`` of the first matching record at or after *start*, else ``None``."""
