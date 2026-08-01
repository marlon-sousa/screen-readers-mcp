# nvdaMcpBridge tests -- FakeLogCapture, standing in for the LogCapture port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# FAKES: domain/ports/log_capture.py
#
# Holds an in-memory LogJournal so the filters and window bracketing are exercised
# through the real entity rather than re-implemented here.
#
# The level bookkeeping MIRRORS the real adapter's, deliberately: start() records
# the floor to restore and the floor now in force, set_level() moves only the
# latter, and stop() restores what start() saved regardless of any set_level in
# between. An earlier version of this fake tracked levels differently from the
# adapter, which is exactly the gap a fake must not have -- the tests would agree
# with themselves while the shipped adapter did something else.

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

from nvdaMcpBridge.domain.entities.log_journal import LogJournal, wire_level_for
from nvdaMcpBridge.domain.ports.log_capture import LogCapture

if TYPE_CHECKING:
	from nvdaMcpBridge import protocol as p

#: The level a stand-in NVDA is at before any session touches it. NVDA's own
#: default is INFO, so a fake that starts anywhere else would make capturedAtLevel
#: assertions agree with nothing real.
DEFAULT_NVDA_LEVEL: int = 20


@dataclass
class _SliceCall:
	"""Record of a slice() call, for test assertions."""

	start: int
	end: int
	min_level: p.LogLevel | None = None
	contains: list[str] | None = None
	exclude: list[str] | None = None
	fields: list[str] | None = None
	max_entries: int = 200


class FakeLogCapture(LogCapture):
	"""An in-memory :class:`LogCapture` backed by a real LogJournal."""

	def __init__(self, *, fail_on: set[str] | None = None) -> None:
		self._fail_on = fail_on or set()
		self._journal = LogJournal()
		# The stand-in for log.root.level: what "NVDA" is set to right now.
		self._nvda_level: int = DEFAULT_NVDA_LEVEL
		self._previous_level: int | None = None
		self._current_level: p.LogLevel | None = None
		# Public for test assertions.
		self.events: list[tuple[Any, ...]] = []
		self.slice_calls: list[_SliceCall] = []
		#: The "now" slice_last_seconds compares record.created against; a test
		#: sets this directly rather than pulling in a real wall clock.
		self.now: float = 0.0

	# -- port implementation ---------------------------------------------------

	@property
	def current_level(self) -> p.LogLevel:
		if self._current_level is not None:
			return self._current_level
		return self._wire_level(self._nvda_level)

	def start(self, level: p.LogLevel | None) -> None:
		self._record("start", level)
		self._journal.reset()
		self._previous_level = self._nvda_level
		if level is not None:
			self._nvda_level = self._level_number(level)
		self._current_level = level or self._wire_level(self._nvda_level)

	def stop(self) -> None:
		self._record("stop")
		if self._previous_level is not None:
			self._nvda_level = self._previous_level
			self._previous_level = None
		self._current_level = None
		self._journal.reset()

	def position(self) -> int:
		return self._journal.mark()

	def slice(
		self,
		start: int,
		end: int,
		*,
		min_level: p.LogLevel | None = None,
		contains: list[str] | None = None,
		exclude: list[str] | None = None,
		fields: list[str] | None = None,
		max_entries: int = 200,
	) -> tuple[str, int, int, bool]:
		self.slice_calls.append(
			_SliceCall(
				start=start,
				end=end,
				min_level=min_level,
				contains=contains,
				exclude=exclude,
				fields=fields,
				max_entries=max_entries,
			)
		)
		return self._journal.slice(
			start,
			end,
			min_level=min_level.value if min_level else None,
			contains=contains,
			exclude=exclude,
			fields=fields,
			max_entries=max_entries,
		)

	def slice_since(
		self,
		position: int,
		*,
		min_level: p.LogLevel | None = None,
		contains: list[str] | None = None,
		exclude: list[str] | None = None,
		fields: list[str] | None = None,
		max_entries: int = 200,
	) -> tuple[str, int, int, bool]:
		return self._journal.slice_since(
			position,
			min_level=min_level.value if min_level else None,
			contains=contains,
			exclude=exclude,
			fields=fields,
			max_entries=max_entries,
		)

	def slice_last_seconds(
		self,
		seconds: float,
		*,
		min_level: p.LogLevel | None = None,
		contains: list[str] | None = None,
		exclude: list[str] | None = None,
		fields: list[str] | None = None,
		max_entries: int = 200,
	) -> tuple[str, int, int, bool]:
		return self._journal.slice_last_seconds(
			seconds,
			self.now,
			min_level=min_level.value if min_level else None,
			contains=contains,
			exclude=exclude,
			fields=fields,
			max_entries=max_entries,
		)

	def find_since(
		self,
		start: int,
		*,
		min_level: p.LogLevel | None = None,
		contains: list[str] | None = None,
	) -> tuple[int, str] | None:
		return self._journal.find_since(
			start,
			min_level=min_level.value if min_level else None,
			contains=contains,
		)

	def set_level(self, level: p.LogLevel) -> None:
		self._record("set_level", level)
		# NOT _previous_level: stop() restores what the session STARTED from, so a
		# set_level in between must not become the thing teardown restores.
		self._nvda_level = self._level_number(level)
		self._current_level = level

	# -- helpers ---------------------------------------------------------------

	@staticmethod
	def _wire_level(level_no: int) -> p.LogLevel:
		from nvdaMcpBridge import protocol

		return protocol.LogLevel(wire_level_for(level_no))

	@staticmethod
	def _level_number(level: p.LogLevel) -> int:
		"""NVDA's logger number for a wire level (IO is 12, above DEBUG's 10)."""
		return {
			"debug": 10,
			"io": 12,
			"debugwarning": 15,
			"info": 20,
			"warning": 30,
			"error": 40,
		}[level.value]

	def _record(self, name: str, *args: Any) -> None:
		self.events.append((name, *args))
		if name in self._fail_on:
			raise RuntimeError(f"log capture failing on {name}")

	def feed(
		self,
		message: str,
		*,
		level_no: int = 20,
		level_name: str = "INFO",
		module: str = "test.module",
		timestamp: str = "12:00:00.000",
		thread: str = "MainThread",
		thread_id: int = 1,
		created: float = 0.0,
	) -> None:
		"""Add a record to the journal (for tests that need content to slice)."""
		self._journal.append(level_no, level_name, module, message, timestamp, thread, thread_id, created)

	def feed_record(
		self,
		level_no: int,
		level_name: str,
		module: str,
		message: str,
		timestamp: str = "12:00:00.000",
		thread: str = "MainThread",
		thread_id: int = 1,
		created: float = 0.0,
	) -> None:
		"""Add a fully specified record to the journal."""
		self._journal.append(level_no, level_name, module, message, timestamp, thread, thread_id, created)
