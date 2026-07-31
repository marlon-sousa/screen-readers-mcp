# nvdaMcpBridge domain -- the LogCapture port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: a private, session-scoped journal of NVDA's own diagnostic log -- distinct
# from the Transcript (spec 0003), which is the bridge's own domain vocabulary.
# USED BY: the hello handler (start), SetLogLevelHandler (current_level/set_level),
# GetLogHandler (position/slice) and the Session (position/current_level to bracket
# each command's window; stop, unconditionally, in teardown).
# IMPLEMENTED BY: adapters/nvda_log_capture.py (a real handler on NVDA's logger);
#                 tests/fakes/log_capture.py FakeLogCapture (records in memory).
#
# Debugging an add-on today means a manual ritual: mark nvda.log, run the repro,
# mark again, copy the slice out. This automates that: the Session brackets every
# command with a journal position, so a slice is exactly one command's window,
# filtered before it crosses the wire (spec 0020). 0009's parallel capture FILE is
# superseded -- the level raise is global, so NVDA's own nvda.log already holds
# identical records, and the transcript's timestamps bracket the window in it.
#
# ``start`` is always called (capture is on for every session); the optional level
# is a temporary, real change to NVDA's own logging -- not a filter private to the
# journal -- because a logger only hands a record to any handler once it has
# decided to emit it at all. That is also why ``set_level`` only works FORWARDS: a
# record that was never emitted cannot be recovered by any later filter. ``stop``
# restores whatever level was in effect before ``start``, regardless of any
# ``set_level`` in between, and must be safe to call even if ``start`` was never
# reached (teardown calls it unconditionally, like the transcript's
# ``session_closed``).

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING

if TYPE_CHECKING:
	from ... import protocol


class LogCapture(ABC):
	"""A per-session journal of NVDA's own log, with an adjustable level."""

	@abstractmethod
	def start(self, level: protocol.LogLevel | None) -> None: ...

	@abstractmethod
	def stop(self) -> None: ...

	@property
	@abstractmethod
	def current_level(self) -> protocol.LogLevel:
		"""The log floor currently in force (for ``capturedAtLevel`` reporting)."""

	@abstractmethod
	def set_level(self, level: protocol.LogLevel) -> None:
		"""Change NVDA's logging floor, from now on (spec 0020).

		Only the levels in ``log_journal.SETTABLE_LEVELS`` reach here; ``warning``
		and ``error`` exist in the wire enum as ``minLevel`` filters only.
		"""

	@abstractmethod
	def position(self) -> int:
		"""The journal's current append position, for window bracketing."""

	@abstractmethod
	def slice(
		self, start: int, end: int, *,
		min_level: protocol.LogLevel | None = None,
		contains: list[str] | None = None,
		exclude: list[str] | None = None,
		fields: list[str] | None = None,
		max_entries: int = 200,
	) -> tuple[str, int, int, bool]:
		"""Filter and format ``[start, end)``: ``(text, entries, matched, truncated)``.

		Deliberately NOT a ``LogSliceResult``: only the caller knows which command
		ids the window belongs to, so building the wire result here would mean
		inventing the id fields and having the handler overwrite them.
		"""
