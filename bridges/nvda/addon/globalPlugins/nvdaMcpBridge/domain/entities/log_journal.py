# nvdaMcpBridge domain -- LogJournal: the in-memory ring of NVDA log records.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: entity. A bounded ring of structured log records the journal handler feeds
# and ``getLog`` reads. Pure: takes records as tuples, knows nothing about
# ``logging``. Owns the caps, the window marks, the filters and the formatting.
# USED BY: the NvdaLogCapture adapter (feeds records) and the GetLogHandler (reads
# slices).
# BUILT BY: NvdaLogCapture (one per process, cleared each session via reset()).
#
# Records are (level_no, level_name, module, message, timestamp, thread, thread_id)
# tuples. The ring is bounded at 10 000 records; older ones age out, and a slice
# that spans aged-out records reports ``truncated: true``. A 4 MB secondary cap is
# tracked approximately via the cumulated length of each record's formatted line;
# whichever cap fires first wins.
#
# Window marks are integer positions into the append stream. Because the ring
# overwrites old records, a mark older than the oldest surviving record is
# "expired" -- getLog reports truncated in that case, and the slice contains only
# what survived.
#
# The rendered line reproduces NVDA's OWN log format (logHandler.Formatter):
#
#     LEVEL - module (time) - thread (thread_id):
#     message
#
# so a slice pasted into an issue reads like nvda.log. Field projection drops
# tokens out of that shape rather than switching to a different one.

from __future__ import annotations

import logging
from collections import deque
from itertools import islice

#: Maximum number of records held in the ring.
MAX_RECORDS: int = 10_000

#: Approximate maximum memory in bytes (the sum of formatted-line lengths).
MAX_BYTES: int = 4 * 1024 * 1024

#: The fields a slice renders by default, in order.
DEFAULT_FIELDS: tuple[str, ...] = ("time", "level", "module", "message")

#: Every field a slice may render. An unknown name is an error rather than a
#: silent omission: a typo'd projection would otherwise return plausible-looking
#: text with a column quietly missing.
FIELD_NAMES: frozenset[str] = frozenset(
	{"time", "level", "module", "message", "thread", "thread_id"}
)

#: Map wire log-level names to NVDA's own logger level numbers, for comparison.
#: These are NVDA's numbers, not guesses: ``logHandler.Logger`` imports the
#: standard levels and defines IO = 12 and DEBUGWARNING = 15 (source/logHandler.py).
#: Note IO sits ABOVE DEBUG (10), not below it.
_LEVEL_ORDER: dict[str, int] = {
	"debug": logging.DEBUG,  # 10
	"io": 12,  # NVDA's custom IO level, between DEBUG (10) and DEBUGWARNING (15)
	"debugwarning": 15,  # NVDA's custom DEBUGWARNING
	"info": logging.INFO,  # 20
	"warning": logging.WARNING,  # 30
	"error": logging.ERROR,  # 40
}

#: The levels that may be SET on NVDA's own logger, as opposed to merely filtered
#: on. ``warning`` and ``error`` exist in the wire enum because they are the common
#: case for ``minLevel``; setting NVDA's floor to either would silence the human's
#: own nvda.log for the rest of the session, which is not ours to do. Mirrors the
#: server's entities.ParseReaderLogLevel.
SETTABLE_LEVELS: frozenset[str] = frozenset({"debug", "io", "debugwarning", "info"})


def wire_level_for(level_no: int) -> str:
	"""The wire level name for one of NVDA's logger level numbers.

	Used to report ``capturedAtLevel`` for a session that never asked for a level
	and so is running at whatever floor the user's NVDA already had. Picks the
	coarsest level whose threshold the floor still admits; a floor below DEBUG
	(NOTSET, say) emits everything, so it reports the most verbose level rather
	than inventing one below it.
	"""
	best = "debug"
	best_no = -1
	for name, threshold in _LEVEL_ORDER.items():
		if threshold <= level_no and threshold > best_no:
			best, best_no = name, threshold
	return best


class LogJournal:
	"""Bounded in-memory ring of structured NVDA log records."""

	def __init__(self) -> None:
		# The ring: each entry is (level_no, level_name, module, message, timestamp, thread, thread_id).
		self._records: deque[tuple[int, str, str, str, str, str, int]] = deque()
		# Monotonic append counter; every append increments it, even when the ring
		# drops old records. This is the value mark() returns, and the coordinate
		# space slice() uses.
		self._next_position: int = 0
		# The position of the oldest record still in the ring. When a mark is below
		# this, the window has aged out.
		self._oldest_position: int = 0
		# Approximate memory tracking: sum of formatted-line lengths.
		self._byte_size: int = 0

	# -- feeding ---------------------------------------------------------------

	def append(
		self,
		level_no: int,
		level_name: str,
		module: str,
		message: str,
		timestamp: str,
		thread: str,
		thread_id: int,
	) -> None:
		"""Add one record to the ring, evicting the oldest if at capacity."""
		record = (level_no, level_name, module, message, timestamp, thread, thread_id)
		self._records.append(record)
		self._next_position += 1
		self._byte_size += self._estimate_size(record)
		while len(self._records) > MAX_RECORDS or self._byte_size > MAX_BYTES:
			old = self._records.popleft()
			self._oldest_position += 1
			self._byte_size -= self._estimate_size(old)

	# -- window marks ----------------------------------------------------------

	def mark(self) -> int:
		"""Return the current append position (for use as a window bound)."""
		return self._next_position

	# -- slicing ---------------------------------------------------------------

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
		"""Return formatted text for records in ``[start, end)`` after applying filters.

		Returns ``(text, entries, matched, truncated)``. Raises ``ValueError`` for an
		unknown ``min_level`` or an unknown field name.
		"""
		min_level_no = self._level_number(min_level)
		use_fields = self._validated_fields(fields)

		# How many positions have aged out of the ring?  If the caller's start is
		# before our oldest, the window is partially truncated.
		truncated = self._oldest_position > start

		# The surviving slice within the ring. islice walks the deque rather than
		# copying all of it, which matters at the 10 000-record cap.
		first = max(start, self._oldest_position)
		offset = first - self._oldest_position
		count = max(0, end - first)
		surviving = islice(self._records, offset, offset + count)

		contains_lower = [c.lower() for c in contains] if contains else None
		exclude_lower = [e.lower() for e in exclude] if exclude else None

		filtered: list[tuple[int, str, str, str, str, str, int]] = []
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

	# -- helpers ---------------------------------------------------------------

	def reset(self) -> None:
		"""Empty the ring (called when a session ends)."""
		self._records.clear()
		self._next_position = 0
		self._oldest_position = 0
		self._byte_size = 0

	@staticmethod
	def _level_number(min_level: str | None) -> int | None:
		"""The threshold for *min_level*, or None when no level was asked for."""
		if min_level is None:
			return None
		try:
			return _LEVEL_ORDER[min_level.lower()]
		except KeyError:
			valid = ", ".join(sorted(_LEVEL_ORDER))
			raise ValueError(f"unknown log level {min_level!r}: want one of {valid}") from None

	@staticmethod
	def _validated_fields(fields: list[str] | None) -> tuple[str, ...]:
		"""The fields to render, defaulted and checked."""
		if not fields:
			return DEFAULT_FIELDS
		unknown = [f for f in fields if f not in FIELD_NAMES]
		if unknown:
			valid = ", ".join(sorted(FIELD_NAMES))
			raise ValueError(f"unknown log field(s) {', '.join(unknown)}: want any of {valid}")
		return tuple(fields)

	@staticmethod
	def _format(
		rec: tuple[int, str, str, str, str, str, int],
		fields: tuple[str, ...],
	) -> str:
		"""Render one record, in NVDA's own log shape, with the selected fields.

		The tokens follow logHandler.Formatter's layout -- ``time`` rides in
		parentheses after ``module``, ``thread_id`` after ``thread``, and
		``message`` starts its own line -- so the full field set reproduces an
		nvda.log line exactly and a projection is that line with tokens removed.
		"""
		_level_no, level_name, module, message, timestamp, thread, thread_id = rec
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
		rec: tuple[int, str, str, str, str, str, int],
	) -> int:
		"""Rough byte estimate: level name + module + message + timestamp + overhead."""
		return len(rec[1]) + len(rec[2]) + len(rec[3]) + len(rec[4]) + len(rec[5]) + 100
