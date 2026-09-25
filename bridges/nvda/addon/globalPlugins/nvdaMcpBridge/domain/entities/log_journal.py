# nvdaMcpBridge domain -- LogJournal: the in-memory ring of NVDA log records.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: entity, a bounded ring of structured NVDA log records, with its window marks, filters and formatting.
# USED BY: the NvdaLogCapture adapter, which feeds it, and the GetLogHandler, which reads slices.
# BUILT BY: NvdaLogCapture, one per process, cleared each session via reset().
# Positions count every append ever made, so a mark older than the oldest surviving record reports truncation.

from __future__ import annotations

import logging
from collections import deque
from itertools import islice

MAX_RECORDS: int = 10_000

MAX_BYTES: int = 4 * 1024 * 1024

DEFAULT_FIELDS: tuple[str, ...] = ("time", "level", "module", "message")

# An unknown field is an error: a typo would otherwise silently drop a column.
FIELD_NAMES: frozenset[str] = frozenset({"time", "level", "module", "message", "thread", "thread_id"})

# NVDA 2026.1's logHandler defines IO = 12 and DEBUGWARNING = 15, so IO sits above DEBUG.
_LEVEL_ORDER: dict[str, int] = {
	"debug": logging.DEBUG,  # 10
	"io": 12,  # NVDA's custom IO level, between DEBUG (10) and DEBUGWARNING (15)
	"debugwarning": 15,  # NVDA's custom DEBUGWARNING
	"info": logging.INFO,  # 20
	"warning": logging.WARNING,  # 30
	"error": logging.ERROR,  # 40
}

# Setting NVDA's floor to warning or error would silence the user's own nvda.log.
SETTABLE_LEVELS: frozenset[str] = frozenset({"debug", "io", "debugwarning", "info"})


def wire_level_for(level_no: int) -> str:
	"""A floor below DEBUG reports the most verbose level rather than inventing one below it."""
	best = "debug"
	best_no = -1
	for name, threshold in _LEVEL_ORDER.items():
		if threshold <= level_no and threshold > best_no:
			best, best_no = name, threshold
	return best


class LogJournal:
	def __init__(self) -> None:
		# ``created`` is epoch seconds for lastSeconds; ``timestamp`` is NVDA's time-only text.
		self._records: deque[tuple[int, str, str, str, str, str, int, float]] = deque()
		self._next_position: int = 0
		self._oldest_position: int = 0
		self._byte_size: int = 0

	def append(
		self,
		level_no: int,
		level_name: str,
		module: str,
		message: str,
		timestamp: str,
		thread: str,
		thread_id: int,
		created: float = 0.0,
	) -> None:
		record = (level_no, level_name, module, message, timestamp, thread, thread_id, created)
		self._records.append(record)
		self._next_position += 1
		self._byte_size += self._estimate_size(record)
		while len(self._records) > MAX_RECORDS or self._byte_size > MAX_BYTES:
			old = self._records.popleft()
			self._oldest_position += 1
			self._byte_size -= self._estimate_size(old)

	def mark(self) -> int:
		return self._next_position

	def slice(
		self,
		start: int,
		end: int,
		*,
		min_level: str | None = None,
		contains: list[str] | None = None,
		exclude: list[str] | None = None,
		fields: list[str] | None = None,
		max_entries: int = 200,
	) -> tuple[str, int, int, bool]:
		"""Return ``(text, entries, matched, truncated)``; raises ``ValueError`` on an unknown name."""
		min_level_no = self._level_number(min_level)
		use_fields = self._validated_fields(fields)

		truncated = self._oldest_position > start

		first = max(start, self._oldest_position)
		offset = first - self._oldest_position
		count = max(0, end - first)
		surviving = islice(self._records, offset, offset + count)

		contains_lower = [c.lower() for c in contains] if contains else None
		exclude_lower = [e.lower() for e in exclude] if exclude else None

		filtered: list[tuple[int, str, str, str, str, str, int, float]] = []
		for rec in surviving:
			if min_level_no is not None and rec[0] < min_level_no:
				continue
			if contains_lower is not None:
				msg_lower = rec[3].lower()
				if not any(c in msg_lower for c in contains_lower):
					continue
			if exclude_lower is not None:
				mod_lower = rec[2].lower()
				msg_lower = rec[3].lower()
				if any(e in mod_lower or e in msg_lower for e in exclude_lower):
					continue
			filtered.append(rec)

		matched = len(filtered)
		if matched > max_entries:
			filtered = filtered[:max_entries]
			truncated = True

		lines = [self._format(rec, use_fields) for rec in filtered]
		return ("\n".join(lines), len(filtered), matched, truncated)

	def slice_since(
		self,
		position: int,
		*,
		min_level: str | None = None,
		contains: list[str] | None = None,
		exclude: list[str] | None = None,
		fields: list[str] | None = None,
		max_entries: int = 200,
	) -> tuple[str, int, int, bool]:
		"""Reading never consumes, so re-issuing the same *position* is idempotent."""
		return self.slice(
			position,
			self._next_position,
			min_level=min_level,
			contains=contains,
			exclude=exclude,
			fields=fields,
			max_entries=max_entries,
		)

	def slice_last_seconds(
		self,
		seconds: float,
		now: float,
		*,
		min_level: str | None = None,
		contains: list[str] | None = None,
		exclude: list[str] | None = None,
		fields: list[str] | None = None,
		max_entries: int = 200,
	) -> tuple[str, int, int, bool]:
		"""With no surviving record after the cutoff, slices an empty range at the current position."""
		cutoff = now - seconds
		start = self._next_position
		for offset, rec in enumerate(self._records):
			if rec[7] >= cutoff:
				start = self._oldest_position + offset
				break
		return self.slice(
			start,
			self._next_position,
			min_level=min_level,
			contains=contains,
			exclude=exclude,
			fields=fields,
			max_entries=max_entries,
		)

	def find_since(
		self,
		start: int,
		*,
		min_level: str | None = None,
		contains: list[str] | None = None,
	) -> tuple[int, str] | None:
		"""The returned position is one past the match, usable as the next ``sincePosition``."""
		min_level_no = self._level_number(min_level)
		contains_lower = [c.lower() for c in contains] if contains else None

		first = max(start, self._oldest_position)
		offset = first - self._oldest_position
		for order, rec in enumerate(islice(self._records, offset, None), start=first):
			if min_level_no is not None and rec[0] < min_level_no:
				continue
			if contains_lower is not None:
				msg_lower = rec[3].lower()
				if not any(c in msg_lower for c in contains_lower):
					continue
			return order + 1, self._format(rec, DEFAULT_FIELDS)
		return None

	def reset(self) -> None:
		self._records.clear()
		self._next_position = 0
		self._oldest_position = 0
		self._byte_size = 0

	@staticmethod
	def _level_number(min_level: str | None) -> int | None:
		if min_level is None:
			return None
		try:
			return _LEVEL_ORDER[min_level.lower()]
		except KeyError:
			valid = ", ".join(sorted(_LEVEL_ORDER))
			raise ValueError(f"unknown log level {min_level!r}: want one of {valid}") from None

	@staticmethod
	def _validated_fields(fields: list[str] | None) -> tuple[str, ...]:
		if not fields:
			return DEFAULT_FIELDS
		unknown = [f for f in fields if f not in FIELD_NAMES]
		if unknown:
			valid = ", ".join(sorted(FIELD_NAMES))
			raise ValueError(f"unknown log field(s) {', '.join(unknown)}: want any of {valid}")
		return tuple(fields)

	@staticmethod
	def _format(
		rec: tuple[int, str, str, str, str, str, int, float],
		fields: tuple[str, ...],
	) -> str:
		"""With every field selected, this reproduces an nvda.log line exactly."""
		_level_no, level_name, module, message, timestamp, thread, thread_id, _created = rec
		selected = frozenset(fields)
		head: list[str] = []
		if "level" in selected:
			head.append(level_name)
		if "module" in selected and "time" in selected:
			head.append(f"{module} ({timestamp})")
		elif "module" in selected:
			head.append(module)
		elif "time" in selected:
			head.append(f"({timestamp})")
		if "thread" in selected and "thread_id" in selected:
			head.append(f"{thread} ({thread_id})")
		elif "thread" in selected:
			head.append(thread)
		elif "thread_id" in selected:
			head.append(f"({thread_id})")
		header = " - ".join(head)
		if "message" not in selected:
			return header
		return f"{header}:\n{message}" if header else message

	@staticmethod
	def _estimate_size(
		rec: tuple[int, str, str, str, str, str, int, float],
	) -> int:
		return len(rec[1]) + len(rec[2]) + len(rec[3]) + len(rec[4]) + len(rec[5]) + 100
